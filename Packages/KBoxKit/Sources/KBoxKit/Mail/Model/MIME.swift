import Foundation

/// Header fields of a message or MIME part. Names are lowercased; values are unfolded and
/// decoded from bytes, but encoded-words (`=?utf-8?B?…?=`) are left for the caller.
struct MIMEHeaders: Sendable {
    var fields: [(name: String, value: String)] = []

    subscript(name: String) -> String? {
        fields.first { $0.name == name }?.value
    }

    func values(_ name: String) -> [String] {
        fields.filter { $0.name == name }.map(\.value)
    }
}

/// One node of a message's MIME tree. `body` is still transfer-encoded.
struct MIMEPart: Sendable {
    var headers: MIMEHeaders
    /// Lowercased `type/subtype`.
    var type: String
    var params: [String: String]
    var body: Data
    var children: [MIMEPart] = []

    var charset: String? { params["charset"] }

    var transferEncoding: String {
        headers["content-transfer-encoding"]?.trimmingCharacters(in: .whitespaces).lowercased() ?? "7bit"
    }

    /// `attachment` / `inline`, lowercased.
    var disposition: String? {
        headers["content-disposition"].map { MIME.parameterized($0).value }
    }

    /// The attachment's name, without any path a sender's client left in it (`C:\fakepath\a.doc`).
    var filename: String? {
        let raw = headers["content-disposition"].flatMap { MIME.parameterized($0).params["filename"] } ?? params["name"]
        guard let raw else { return nil }
        let name = MIME.decodeWords(raw).split(whereSeparator: { $0 == "/" || $0 == "\\" }).last
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let name, !name.isEmpty, name != ".", name != ".." else { return nil }
        return name
    }

    var contentID: String? {
        guard let raw = headers["content-id"]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
    }

    var decodedBody: Data {
        switch transferEncoding {
        case "base64": MIME.decodeBase64(body)
        case "quoted-printable": MIME.decodeQuotedPrintable(body)
        default: body
        }
    }

    var text: String {
        let data = decodedBody
        var charset = charset
        // HTML often carries its real charset only in a <meta> tag.
        if type == "text/html", charset.map({ ["us-ascii", "ascii"].contains($0.lowercased()) }) ?? true,
           let sniffed = MIME.sniffHTMLCharset(data) {
            charset = sniffed
        }
        return MIME.decode(data, charset: charset)
    }

    static func parse(_ data: Data, defaultType: String = "text/plain", depth: Int = 0) -> MIMEPart {
        let (headers, body) = MIME.parseHeaders(data)
        let (type, params) = MIME.parameterized(headers["content-type"] ?? defaultType)
        var part = MIMEPart(headers: headers, type: type.isEmpty ? defaultType : type, params: params, body: body)
        if part.type.hasPrefix("multipart/") {
            if let boundary = params["boundary"], !boundary.isEmpty, depth < 12 {
                let childType = part.type == "multipart/digest" ? "message/rfc822" : "text/plain"
                part.children = MIME.splitMultipart(body, boundary: boundary)
                    .map { parse($0, defaultType: childType, depth: depth + 1) }
            }
            // A multipart without usable parts: show whatever is there as text.
            if part.children.isEmpty { part.type = "text/plain" }
        }
        return part
    }
}

/// RFC 2045–2047 / 2231 decoding.
enum MIME {
    // MARK: - Headers

    /// Splits header fields from the body at the first blank line, unfolding continuation lines.
    /// Raw 8-bit values are decoded as UTF-8, else as the part's own charset, else GB18030.
    static func parseHeaders(_ data: Data) -> (MIMEHeaders, Data) {
        var raw: [(name: String, value: Data)] = []
        var index = data.startIndex
        var bodyStart = data.endIndex
        while index < data.endIndex {
            let newline = data[index...].firstIndex(of: 0x0A) ?? data.endIndex
            var contentEnd = newline
            if contentEnd > index, data[contentEnd - 1] == 0x0D { contentEnd -= 1 }
            let next = newline < data.endIndex ? newline + 1 : newline
            if contentEnd == index {
                bodyStart = next
                break
            }
            let first = data[index]
            if first == 0x20 || first == 0x09 {
                if !raw.isEmpty { raw[raw.count - 1].value.append(data[index..<contentEnd]) }
            } else if let colon = data[index..<contentEnd].firstIndex(of: 0x3A),
                      let nameEnd = headerNameEnd(data, from: index, colon: colon) {
                var valueStart = colon + 1
                while valueStart < contentEnd, data[valueStart] == 0x20 || data[valueStart] == 0x09 { valueStart += 1 }
                let name = String(decoding: data[index..<nameEnd], as: UTF8.self).lowercased()
                raw.append((name, Data(data[valueStart..<contentEnd])))
            } else {
                // Not a header line: the header block ended without a blank line.
                bodyStart = index
                break
            }
            index = next
        }

        let fallback = raw.first { $0.name == "content-type" }
            .flatMap { parameterized(String(decoding: $0.value, as: UTF8.self)).params["charset"] }
        var headers = MIMEHeaders()
        headers.fields = raw.map { field in
            let value = field.value.allSatisfy { $0 < 0x80 }
                ? String(decoding: field.value, as: UTF8.self)
                : decodeUndeclared(field.value, charset: fallback)
            return (name: field.name, value: value)
        }
        return (headers, data[bodyStart..<data.endIndex])
    }

    /// End of a field name: printable ASCII up to the colon, allowing the obsolete `Subject :` form.
    private static func headerNameEnd(_ data: Data, from start: Data.Index, colon: Data.Index) -> Data.Index? {
        var end = colon
        while end > start, data[end - 1] == 0x20 || data[end - 1] == 0x09 { end -= 1 }
        guard end > start, data[start..<end].allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else { return nil }
        return end
    }

    /// `text/plain; charset="gb2312"; name*=UTF-8''%E4%BD%A0.txt` → ("text/plain", params).
    /// Parameter names are lowercased; RFC 2231 continuations and charsets are resolved.
    static func parameterized(_ raw: String) -> (value: String, params: [String: String]) {
        var segments: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for character in raw {
            if escaped {
                // Only \" and \\ are escapes in practice; Windows paths keep their backslashes.
                if character != "\"" && character != "\\" { current.append("\\") }
                current.append(character)
                escaped = false
            } else if character == "\\" && inQuotes {
                escaped = true
            } else if character == "\"" {
                inQuotes.toggle()
                current.append(character)
            } else if character == ";" && !inQuotes {
                segments.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        segments.append(current)

        let value = segments[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var plain: [String: String] = [:]
        var extended: [String: [(section: Int, value: String, encoded: Bool)]] = [:]
        for segment in segments.dropFirst() {
            guard let equals = segment.firstIndex(of: "=") else { continue }
            let name = segment[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var parameter = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if parameter.count >= 2, parameter.hasPrefix("\""), parameter.hasSuffix("\"") {
                parameter = String(parameter.dropFirst().dropLast())
            }
            guard !name.isEmpty else { continue }
            if let star = name.firstIndex(of: "*") {
                let base = String(name[..<star])
                let rest = name[name.index(after: star)...]
                let encoded = rest.isEmpty || rest.hasSuffix("*")
                let section = Int(rest.trimmingCharacters(in: CharacterSet(charactersIn: "*"))) ?? 0
                extended[base, default: []].append((section, parameter, encoded))
            } else {
                plain[name] = parameter
            }
        }
        for (name, sections) in extended {
            var charset: String?
            var bytes = Data()
            for (offset, section) in sections.sorted(by: { $0.section < $1.section }).enumerated() {
                var text = Substring(section.value)
                if section.encoded {
                    if offset == 0, let first = text.firstIndex(of: "'"),
                       let second = text[text.index(after: first)...].firstIndex(of: "'") {
                        charset = String(text[..<first])
                        text = text[text.index(after: second)...]
                    }
                    bytes.append(percentDecode(text))
                } else {
                    bytes.append(Data(text.utf8))
                }
            }
            plain[name] = decode(bytes, charset: charset)
        }
        return (value, plain)
    }

    // MARK: - Encoded words (RFC 2047)

    /// Decodes `=?charset?B|Q?text?=` words. Whitespace between adjacent encoded words is dropped,
    /// and adjacent words in the same charset are decoded together (some senders split a UTF-8
    /// character across two words).
    static func decodeWords(_ value: String) -> String {
        guard value.contains("=?") else { return value }
        let bytes = Array(value.utf8)
        var output = ""
        var literal: [UInt8] = []
        var pending: (charset: String, bytes: Data)?
        var index = 0

        func flushPending() {
            if let pending { output += decode(pending.bytes, charset: pending.charset) }
            pending = nil
        }

        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "="), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "?"),
               let word = encodedWord(bytes, at: index) {
                let onlyWhitespace = literal.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
                if pending != nil, onlyWhitespace {
                    literal.removeAll()
                } else {
                    flushPending()
                    output += String(decoding: literal, as: UTF8.self)
                    literal.removeAll()
                }
                if let current = pending, current.charset == word.charset {
                    pending = (current.charset, current.bytes + word.bytes)
                } else {
                    flushPending()
                    pending = (word.charset, word.bytes)
                }
                index = word.end
            } else {
                if pending != nil, !(bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A || bytes[index] == 0x0D) {
                    flushPending()
                    output += String(decoding: literal, as: UTF8.self)
                    literal.removeAll()
                }
                literal.append(bytes[index])
                index += 1
            }
        }
        flushPending()
        output += String(decoding: literal, as: UTF8.self)
        return output
    }

    private static func encodedWord(_ bytes: [UInt8], at start: Int) -> (charset: String, bytes: Data, end: Int)? {
        let question = UInt8(ascii: "?")
        var index = start + 2
        while index < bytes.count, bytes[index] != question {
            if bytes[index] == 0x20 { return nil }
            index += 1
        }
        guard index + 2 < bytes.count, bytes[index + 2] == question else { return nil }
        var charset = String(decoding: bytes[(start + 2)..<index], as: UTF8.self)
        if let star = charset.firstIndex(of: "*") { charset = String(charset[..<star]) }
        let mode = bytes[index + 1] | 0x20
        let textStart = index + 3
        var end = textStart
        while end + 1 < bytes.count, !(bytes[end] == question && bytes[end + 1] == UInt8(ascii: "=")) { end += 1 }
        guard end + 1 < bytes.count, !charset.isEmpty else { return nil }
        let text = Data(bytes[textStart..<end])
        let decoded: Data
        switch mode {
        case UInt8(ascii: "b"): decoded = decodeBase64(text)
        case UInt8(ascii: "q"): decoded = decodeQuotedPrintable(text, underscoreIsSpace: true)
        default: return nil
        }
        return (charset, decoded, end + 2)
    }

    // MARK: - Transfer encodings

    static func decodeBase64(_ data: Data) -> Data {
        if let decoded = Data(base64Encoded: data, options: .ignoreUnknownCharacters) { return decoded }
        // Missing padding or junk after it: keep the alphabet up to the first "=", then re-pad.
        var clean: [UInt8] = []
        clean.reserveCapacity(data.count)
        loop: for byte in data {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "+"), UInt8(ascii: "/"):
                clean.append(byte)
            case UInt8(ascii: "="):
                break loop
            default:
                continue
            }
        }
        switch clean.count % 4 {
        case 1: clean.removeLast()
        case 2: clean += Array("==".utf8)
        case 3: clean.append(UInt8(ascii: "="))
        default: break
        }
        return Data(base64Encoded: Data(clean)) ?? Data()
    }

    static func decodeQuotedPrintable(_ data: Data, underscoreIsSpace: Bool = false) -> Data {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Data in
            var output: [UInt8] = []
            output.reserveCapacity(buffer.count)
            var index = 0
            while index < buffer.count {
                let byte = buffer[index]
                if byte == UInt8(ascii: "=") {
                    // Soft line break, possibly with trailing whitespace before it.
                    var lookahead = index + 1
                    while lookahead < buffer.count, buffer[lookahead] == 0x20 || buffer[lookahead] == 0x09 { lookahead += 1 }
                    if lookahead == buffer.count {
                        index = lookahead
                        continue
                    }
                    if buffer[lookahead] == 0x0A {
                        index = lookahead + 1
                        continue
                    }
                    if buffer[lookahead] == 0x0D, lookahead + 1 < buffer.count, buffer[lookahead + 1] == 0x0A {
                        index = lookahead + 2
                        continue
                    }
                    if index + 2 < buffer.count, let high = hexValue(buffer[index + 1]), let low = hexValue(buffer[index + 2]) {
                        output.append(high << 4 | low)
                        index += 3
                        continue
                    }
                    output.append(byte)
                } else if byte == UInt8(ascii: "_"), underscoreIsSpace {
                    output.append(0x20)
                } else {
                    output.append(byte)
                }
                index += 1
            }
            return Data(output)
        }
    }

    static func percentDecode(_ text: Substring) -> Data {
        let bytes = Array(text.utf8)
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "%"), index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) {
                output.append(high << 4 | low)
                index += 3
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return Data(output)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        default: nil
        }
    }

    // MARK: - Multipart

    /// Bodies of the parts between `--boundary` lines, up to `--boundary--`.
    static func splitMultipart(_ body: Data, boundary: String) -> [Data] {
        let delimiter = Data(("--" + boundary).utf8)
        var parts: [Data] = []
        var searchStart = body.startIndex
        var partStart: Data.Index?
        while searchStart < body.endIndex, let found = body.range(of: delimiter, in: searchStart..<body.endIndex) {
            searchStart = found.upperBound
            guard found.lowerBound == body.startIndex || body[found.lowerBound - 1] == 0x0A else { continue }
            let after = found.upperBound
            let isClosing = after + 1 < body.endIndex && body[after] == 0x2D && body[after + 1] == 0x2D
            // "--boundaryX" is a different boundary that merely starts with ours.
            if !isClosing, after < body.endIndex, ![0x0A, 0x0D, 0x20, 0x09].contains(body[after]) { continue }

            if let start = partStart {
                var end = found.lowerBound
                if end > start, body[end - 1] == 0x0A { end -= 1 }
                if end > start, body[end - 1] == 0x0D { end -= 1 }
                parts.append(body[start..<end])
            }
            if isClosing { return parts }
            guard let newline = body[after...].firstIndex(of: 0x0A) else { return parts }
            partStart = newline + 1
            searchStart = newline + 1
        }
        // No closing delimiter: the last part runs to the end.
        if let start = partStart, start < body.endIndex { parts.append(body[start..<body.endIndex]) }
        return parts
    }

    // MARK: - Charsets

    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    static func encoding(forCharset name: String) -> String.Encoding? {
        var charset = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t")).lowercased()
        // Junk after the name ("utf-8 format=flowed"), and Outlook's "_iso-2022-jp$esc".
        if let end = charset.firstIndex(where: { $0 == " " || $0 == ";" || $0 == "$" }) { charset = String(charset[..<end]) }
        if charset.hasPrefix("_") { charset.removeFirst() }
        switch charset {
        case "utf-8", "utf8", "utf_8", "us-ascii", "ascii", "ansi_x3.4-1968", "646":
            return .utf8
        case "gb2312", "gbk", "x-gbk", "cp936", "gb18030", "euc-cn", "x-euc-cn", "chinese", "csgb2312",
             "gb_2312-80", "gb2312-80", "x-gb2312":
            return gb18030
        case "iso-8859-1", "latin1", "latin-1", "l1":
            return .windowsCP1252
        default:
            let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            guard encoding != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
        }
    }

    /// Text in the declared charset; when that is missing or wrong, UTF-8, then GB18030, then lossy UTF-8.
    static func decode(_ data: Data, charset: String?) -> String {
        guard !data.isEmpty else { return "" }
        if let charset, let encoding = encoding(forCharset: charset) {
            // "Latin-1" that is valid multi-byte UTF-8 is mislabelled UTF-8: real Latin-1 text almost never is.
            if encoding == .windowsCP1252 || encoding == .isoLatin1, data.contains(where: { $0 >= 0x80 }),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return decodeUndeclared(data, charset: nil)
    }

    /// The charset named in an HTML document's `<meta>` tag, from its first 2 KB.
    static func sniffHTMLCharset(_ data: Data) -> String? {
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        guard let meta = head.range(of: "<meta"), let found = head.range(of: "charset=", range: meta.lowerBound..<head.endIndex)
        else { return nil }
        let name = head[found.upperBound...].drop { $0 == "\"" || $0 == "'" || $0 == " " }
            .prefix { $0.isLetter || $0.isNumber || "-_:.".contains($0) }
        return name.isEmpty ? nil : String(name)
    }

    /// Bytes with no reliable label (raw 8-bit headers): UTF-8 first, then the hint, then GB18030.
    static func decodeUndeclared(_ data: Data, charset: String?) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let charset, let encoding = encoding(forCharset: charset), let text = String(data: data, encoding: encoding) {
            return text
        }
        if let text = String(data: data, encoding: gb18030) { return text }
        return String(decoding: data, as: UTF8.self)
    }
}
