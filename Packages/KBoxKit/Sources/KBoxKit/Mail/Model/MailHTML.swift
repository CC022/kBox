import Foundation

/// Turning message bodies into what the reader's web view loads, and HTML into searchable text.
enum MailHTML {
    // MARK: - HTML → text

    private static let skippedElements: Set<String> = ["style", "script", "head", "title"]
    private static let blockElements: Set<String> = [
        "br", "p", "div", "tr", "li", "ul", "ol", "table", "blockquote", "pre", "hr",
        "h1", "h2", "h3", "h4", "h5", "h6",
    ]
    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "middot": "·", "bull": "•",
        "yen": "¥", "euro": "€", "pound": "£", "times": "×", "zwnj": "", "zwj": "", "shy": "",
    ]

    /// Visible text of an HTML document: tags dropped, block elements as line breaks, entities decoded.
    static func text(fromHTML html: String) -> String {
        let bytes = Array(html.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count / 2)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "<") {
                if starts(bytes, at: index, with: "<!--") {
                    index = find(bytes, "-->", from: index + 4).map { $0 + 3 } ?? bytes.count
                    continue
                }
                var nameEnd = index + 1
                let closing = nameEnd < bytes.count && bytes[nameEnd] == UInt8(ascii: "/")
                if closing { nameEnd += 1 }
                let nameStart = nameEnd
                while nameEnd < bytes.count, isAlphanumeric(bytes[nameEnd]) { nameEnd += 1 }
                let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self).lowercased()
                let isDeclaration = !closing && name.isEmpty && nameEnd < bytes.count && bytes[nameEnd] == UInt8(ascii: "!")
                guard name.first?.isLetter == true || isDeclaration,
                      let tagEnd = bytes[nameEnd...].firstIndex(of: UInt8(ascii: ">"))
                else {
                    output.append(byte) // a stray "<"
                    index += 1
                    continue
                }
                if !closing, skippedElements.contains(name) {
                    let close = find(bytes, "</\(name)", from: tagEnd, caseInsensitive: true)
                    index = close.flatMap { bytes[$0...].firstIndex(of: UInt8(ascii: ">")) }.map { $0 + 1 } ?? bytes.count
                    continue
                }
                if blockElements.contains(name) { output.append(0x0A) }
                if name == "td" || name == "th" { output.append(0x20) }
                index = tagEnd + 1
            } else if byte == UInt8(ascii: "&"), let (decoded, length) = entity(bytes, at: index) {
                output += decoded.utf8
                index += length
            } else {
                output.append(byte)
                index += 1
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func entity(_ bytes: [UInt8], at start: Int) -> (String, Int)? {
        var end = start + 1
        while end < bytes.count, end - start <= 10, bytes[end] != UInt8(ascii: ";") { end += 1 }
        guard end < bytes.count, bytes[end] == UInt8(ascii: ";"), end > start + 1 else { return nil }
        let name = String(decoding: bytes[(start + 1)..<end], as: UTF8.self)
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return (String(Character(scalar)), end - start + 1)
        }
        guard let text = entities[name.lowercased()] else { return nil }
        return (text, end - start + 1)
    }

    // MARK: - Documents for the web view

    private static let fontSize: Int = {
        #if os(macOS)
        14
        #else
        17
        #endif
    }()

    private static func policy(allowRemote: Bool) -> String {
        allowRemote
            ? "default-src * data: blob: 'unsafe-inline'; script-src 'none'; object-src 'none'"
            : "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; media-src data:"
    }

    private static func head(allowRemote: Bool, colorScheme: String, extraCSS: String) -> String {
        """
        <meta http-equiv="Content-Security-Policy" content="\(policy(allowRemote: allowRemote))">\
        <meta http-equiv="x-dns-prefetch-control" content="off">\
        <meta name="viewport" content="width=device-width, initial-scale=1">\
        <style>:root { color-scheme: \(colorScheme); } \
        body { margin: 16px 20px; font-family: -apple-system, "PingFang SC", sans-serif; font-size: \(fontSize)px; \
        line-height: 1.45; overflow-wrap: break-word; } \
        mark[data-kbox] { background: #ffd60a; color: #000; border-radius: 2px; } \
        .kbox-forwarded { margin-top: 20px; padding-top: 12px; border-top: 1px solid #c8c8c8; } \
        \(extraCSS)</style>
        """
    }

    /// The page the reader loads. Page scripts never run; remote images, styles and fonts are blocked
    /// unless `allowRemote`. HTML mail keeps a white page (it is designed for one); plain text follows
    /// the system appearance.
    static func document(for content: MailContent, allowRemote: Bool) -> String {
        if let html = content.html {
            return document(html: html, allowRemote: allowRemote)
        }
        return document(plainText: content.plainText ?? "")
    }

    static func document(html: String, allowRemote: Bool) -> String {
        let head = head(allowRemote: allowRemote, colorScheme: "light",
                        extraCSS: "html { background: #fff; color: #000; } img { max-width: 100%; height: auto; }")
        // The policy must come first: content before <head> would move a later meta into <body>,
        // where it is ignored. Only a leading doctype stays in front so the page keeps its mode.
        let trimmed = html.drop { $0.isWhitespace || $0 == "\u{FEFF}" }
        if trimmed.prefix(9).lowercased() == "<!doctype", let end = trimmed.firstIndex(of: ">") {
            return String(trimmed[...end]) + head + String(trimmed[trimmed.index(after: end)...])
        }
        return head + trimmed
    }

    static func document(plainText: String) -> String {
        let css = """
        html, body { background: transparent; } body { white-space: pre-wrap; } \
        blockquote { margin: 4px 0; padding-left: 10px; border-left: 2px solid #5b8fd9; color: #3f6db3; } \
        @media (prefers-color-scheme: dark) { blockquote { border-left-color: #6fa0e8; color: #8fb6f0; } } \
        a { color: LinkText; }
        """
        return "<!DOCTYPE html><html><head>" + head(allowRemote: false, colorScheme: "light dark", extraCSS: css)
            + "</head><body>" + plainTextBody(plainText) + "</body></html>"
    }

    /// Escaped text with links, and runs of `>` quoted lines as nested blockquotes.
    static func plainTextBody(_ text: String) -> String {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var output = ""
        var level = 0
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var depth = 0
            var rest = Substring(line)
            while true {
                let trimmed = rest.drop { $0 == " " }
                guard trimmed.first == ">" else { break }
                depth += 1
                rest = trimmed.dropFirst()
            }
            if depth > 0, rest.first == " " { rest = rest.dropFirst() }
            if depth == level {
                if index > 0 { output += "\n" }
            } else {
                output += depth > level
                    ? String(repeating: "<blockquote>", count: depth - level)
                    : String(repeating: "</blockquote>", count: level - depth)
                level = depth
            }
            output += linkified(String(rest), detector: detector)
        }
        output += String(repeating: "</blockquote>", count: level)
        return output
    }

    private static func linkified(_ line: String, detector: NSDataDetector?) -> String {
        guard let detector, line.contains(where: { $0 == "." || $0 == ":" }) else { return escape(line) }
        let ns = line as NSString
        var output = ""
        var cursor = 0
        for match in detector.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            guard let url = match.url, match.range.location >= cursor else { continue }
            output += escape(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            output += "<a href=\"\(escape(url.absoluteString))\">\(escape(ns.substring(with: match.range)))</a>"
            cursor = match.range.location + match.range.length
        }
        return output + escape(ns.substring(from: cursor))
    }

    static func escape(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            default: output.append(character)
            }
        }
        return output
    }

    /// Whether the HTML loads anything from the network (images, backgrounds, stylesheets).
    static func hasRemoteReferences(_ html: String) -> Bool {
        let lower = html.lowercased()
        var searchStart = lower.startIndex
        while let found = lower.range(of: "http", range: searchStart..<lower.endIndex) {
            searchStart = found.upperBound
            let from = lower.index(found.lowerBound, offsetBy: -16, limitedBy: lower.startIndex) ?? lower.startIndex
            let attribute = lower[from..<found.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'("))
            if ["src=", "srcset=", "background=", "url", "poster=", "@import"].contains(where: { attribute.hasSuffix($0) }) {
                return true
            }
        }
        return false
    }

    // MARK: - Byte helpers

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte | 0x20 >= 0x61 && byte | 0x20 <= 0x7A)
    }

    private static func starts(_ bytes: [UInt8], at index: Int, with prefix: String) -> Bool {
        let prefix = Array(prefix.utf8)
        return index + prefix.count <= bytes.count && Array(bytes[index..<(index + prefix.count)]) == prefix
    }

    private static func find(_ bytes: [UInt8], _ pattern: String, from start: Int, caseInsensitive: Bool = false) -> Int? {
        let pattern = Array(pattern.utf8)
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        var index = start
        while index <= bytes.count - pattern.count {
            var matched = true
            for offset in 0..<pattern.count {
                let a = bytes[index + offset], b = pattern[offset]
                if a != b && !(caseInsensitive && a | 0x20 == b | 0x20 && b | 0x20 >= 0x61 && b | 0x20 <= 0x7A) {
                    matched = false
                    break
                }
            }
            if matched { return index }
            index += 1
        }
        return nil
    }
}
