import Foundation
import UniformTypeIdentifiers

public struct MailAddress: Sendable, Hashable {
    public var name: String
    public var email: String

    public var displayName: String { name.isEmpty ? email : name }

    /// "张三 <zhang@example.com>", or whichever half there is.
    var fullDescription: String {
        name.isEmpty || email.isEmpty ? displayName : "\(name) <\(email)>"
    }

    /// "张" for 张三, "JA" for John Appleseed, "Z" for zhang@example.com.
    public var initials: String {
        let source = name.isEmpty ? String(email.prefix { $0 != "@" }) : name
        guard let first = source.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        if first.unicodeScalars.first?.properties.isIdeographic == true { return String(first) }
        let words = source.split { !($0.isLetter || $0.isNumber) }
        guard name.isEmpty == false, words.count > 1, let last = words.last?.first else { return first.uppercased() }
        return (String(first) + String(last)).uppercased()
    }

    /// Parses an address-list header: `"张三" <zhang@example.com>, li@example.com, Group: a@b;`.
    static func parseList(_ raw: String) -> [MailAddress] {
        var result: [MailAddress] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        var angleDepth = 0
        let characters = Array(raw)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            index += 1
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            // An encoded word is one token: "=?UTF-8?Q?Doe,_John?=" must not split at its comma.
            if character == "=", !inQuotes, index < characters.count, characters[index] == "?",
               let end = encodedWordEnd(characters, from: index - 1) {
                current.append(contentsOf: characters[(index - 1)..<end])
                index = end
                continue
            }
            switch character {
            case "\\" where inQuotes:
                escaped = true
                current.append(character)
            case "\"":
                inQuotes.toggle()
                current.append(character)
            case "<" where !inQuotes:
                angleDepth += 1
                current.append(character)
            case ">" where !inQuotes:
                angleDepth = max(0, angleDepth - 1)
                current.append(character)
            case "," where !inQuotes && angleDepth == 0, ";" where !inQuotes && angleDepth == 0:
                if let address = parseOne(current) { result.append(address) }
                current = ""
            case ":" where !inQuotes && angleDepth == 0 && !current.contains("@"):
                current = "" // group name
            default:
                current.append(character)
            }
        }
        if let address = parseOne(current) { result.append(address) }
        return result
    }

    /// Index just past the `?=` of an encoded word starting at `start` (its `=`), if it is one.
    private static func encodedWordEnd(_ characters: [Character], from start: Int) -> Int? {
        var index = start + 2
        var marks = 0
        while index < characters.count, marks < 2 {
            if characters[index] == "?" { marks += 1 } else if characters[index] == " " { return nil }
            index += 1
        }
        guard marks == 2 else { return nil }
        while index + 1 < characters.count {
            if characters[index] == "?", characters[index + 1] == "=" { return index + 2 }
            index += 1
        }
        return nil
    }

    private static func parseOne(_ raw: String) -> MailAddress? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let open = text.lastIndex(of: "<"), let close = text[open...].firstIndex(of: ">") {
            let email = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            let name = clean(MIME.decodeWords(unquote(String(text[..<open]))))
            return MailAddress(name: name == email ? "" : name, email: email)
        }
        if let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close {
            let name = clean(MIME.decodeWords(String(text[text.index(after: open)..<close])))
            return MailAddress(name: name, email: text[..<open].trimmingCharacters(in: .whitespaces))
        }
        if text.contains("@"), !text.contains(" ") { return MailAddress(name: "", email: text) }
        return MailAddress(name: clean(MIME.decodeWords(unquote(text))), email: "")
    }

    private static func unquote(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            value = String(value.dropFirst().dropLast())
        }
        return value.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
    }
}

/// What the message list shows. `id` is the message's position in the file.
public struct MailSummary: Identifiable, Sendable, Equatable {
    public let id: Int
    public var range: Range<Int>
    public var subject: String
    public var from: MailAddress?
    public var to: [MailAddress]
    public var cc: [MailAddress]
    public var date: Date?
    public var snippet: String
    public var hasAttachments: Bool
}

public struct MailAttachment: Identifiable, Sendable {
    public let id: Int
    public var filename: String
    public var mimeType: String
    public var data: Data

    public var size: Int { data.count }

    public var contentType: UTType {
        UTType(filenameExtension: (filename as NSString).pathExtension) ?? UTType(mimeType: mimeType) ?? .data
    }
}

/// A fully parsed message for the reader.
public struct MailContent: Sendable {
    public var summary: MailSummary
    /// HTML body with `cid:` images inlined as `data:` URLs.
    public var html: String?
    public var plainText: String?
    public var attachments: [MailAttachment]
    public var hasRemoteContent: Bool
}

enum MailParser {
    /// Snippet and search text from the headers and the body text only; attachments are never decoded.
    static func summary(id: Int, slice: MessageSlice, in data: Data) -> (MailSummary, SearchFields) {
        let message = MIMEPart.parse(Mbox.message(slice.range, in: data))
        let headers = message.headers
        let subject = collapseWhitespace(MIME.decodeWords(headers["subject"] ?? ""))
        let from = MailAddress.parseList(headers["from"] ?? headers["sender"] ?? "").first
        let to = MailAddress.parseList(headers["to"] ?? "")
        let cc = MailAddress.parseList(headers["cc"] ?? "")
        // No usable Date: the first (latest) Received hop, then the mbox envelope.
        let date = headers["date"].flatMap(MailDate.parse)
            ?? headers.values("received").lazy.compactMap(MailDate.parseReceived).first
            ?? MailDate.parseEnvelope(slice.envelope)

        var parts = BodyParts()
        collect(message, into: &parts)
        let (plain, html) = bodies(parts)
        let text = (plain ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MailHTML.text(fromHTML: html ?? "")
            : plain ?? ""

        let summary = MailSummary(
            id: id,
            range: slice.range,
            subject: subject,
            from: from,
            to: to,
            cc: cc,
            date: date,
            snippet: String(collapseWhitespace(String(text.prefix(600))).prefix(200)),
            hasAttachments: !parts.attachments.isEmpty
        )
        return (summary, SearchFields(summary: summary, body: text))
    }

    static func content(_ summary: MailSummary, in data: Data) -> MailContent {
        let message = MIMEPart.parse(Mbox.message(summary.range, in: data))
        var parts = BodyParts()
        collect(message, into: &parts)

        var (plain, html) = bodies(parts)
        if plain?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true, html != nil { plain = nil }
        var attachmentParts: [MIMEPart] = []
        for part in parts.inline {
            if var body = html, let id = part.contentID, body.contains("cid:\(id)") {
                let url = "data:\(part.type);base64,\(part.decodedBody.base64EncodedString())"
                body = body.replacingOccurrences(of: "cid:\(id)", with: url)
                html = body
            } else {
                attachmentParts.append(part)
            }
        }
        attachmentParts = parts.attachments + attachmentParts

        let attachments = attachmentParts.enumerated().map { index, part in
            MailAttachment(id: index, filename: part.filename ?? defaultFilename(for: part.type),
                           mimeType: part.type, data: part.decodedBody)
        }
        return MailContent(
            summary: summary,
            html: html,
            plainText: plain,
            attachments: attachments,
            hasRemoteContent: html.map(MailHTML.hasRemoteReferences) ?? false
        )
    }

    // MARK: - Choosing the body

    struct BodyParts {
        var plain: [MIMEPart] = []
        var html: [MIMEPart] = []
        var attachments: [MIMEPart] = []
        /// Parts with a Content-ID that the HTML may reference as `cid:`.
        var inline: [MIMEPart] = []
        /// Messages forwarded inline (message/rfc822 that is not an attachment), already rendered.
        var forwarded: [Forwarded] = []
    }

    struct Forwarded {
        var plain: String
        var html: String
        var hasHTML: Bool
    }

    /// The bodies to show and search: the message's own text parts, then any inline forwarded messages.
    static func bodies(_ parts: BodyParts) -> (plain: String?, html: String?) {
        let plainSections = parts.plain.map(plainText) + parts.forwarded.map(\.plain)
        let plain = plainSections.isEmpty ? nil : plainSections.joined(separator: "\n\n")
        var html: String?
        if !parts.html.isEmpty {
            html = (parts.html.map(\.text) + parts.forwarded.map(\.html)).joined(separator: "\n")
        } else if parts.plain.isEmpty, parts.forwarded.contains(where: \.hasHTML) {
            html = parts.forwarded.map(\.html).joined(separator: "\n")
        }
        return (plain, html)
    }

    /// A text/plain part's text, with `format=flowed` paragraphs rejoined.
    static func plainText(_ part: MIMEPart) -> String {
        let text = part.text
        guard part.params["format"]?.lowercased() == "flowed" else { return text }
        return unflow(text, deleteSpace: part.params["delsp"]?.lowercased() == "yes")
    }

    /// RFC 3676: a line ending in a space continues on the next line at the same quote depth.
    /// Quote markers are re-emitted as "> " so the reader still sees the quote levels.
    static func unflow(_ text: String, deleteSpace: Bool) -> String {
        var output: [String] = []
        var paragraph = ""
        var depth = 0
        var isOpen = false
        func flush() {
            if isOpen { output.append((depth > 0 ? String(repeating: ">", count: depth) + " " : "") + paragraph) }
            paragraph = ""
            isOpen = false
        }
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var line = Substring(raw)
            var lineDepth = 0
            while line.first == ">" {
                lineDepth += 1
                line = line.dropFirst()
            }
            if line.first == " " { line = line.dropFirst() } // space-stuffing
            let isFlowed = line.hasSuffix(" ") && line != "-- "
            if isOpen, lineDepth != depth { flush() }
            if !isOpen {
                depth = lineDepth
                isOpen = true
            }
            paragraph += isFlowed && deleteSpace ? String(line.dropLast()) : String(line)
            if !isFlowed { flush() }
        }
        flush()
        return output.joined(separator: "\n")
    }

    /// Renders an inline forwarded message as a short header block plus its body.
    private static func forwarded(_ part: MIMEPart, depth: Int, into parts: inout BodyParts) {
        let message = MIMEPart.parse(part.decodedBody)
        var inner = BodyParts()
        collect(message, depth: depth + 1, into: &inner)
        let (plain, html) = bodies(inner)

        let headers = message.headers
        let fields: [(String, String)] = [
            ("发件人", MailAddress.parseList(headers["from"] ?? "").map(\.fullDescription).joined(separator: ", ")),
            ("日期", headers["date"].flatMap(MailDate.parse).map { Fmt.mailFullDate($0) } ?? headers["date"] ?? ""),
            ("主题", collapseWhitespace(MIME.decodeWords(headers["subject"] ?? ""))),
            ("收件人", MailAddress.parseList(headers["to"] ?? "").map(\.fullDescription).joined(separator: ", ")),
        ].filter { !$0.1.isEmpty }

        let plainHeader = (["---------- 转发的邮件 ----------"] + fields.map { "\($0.0)：\($0.1)" }).joined(separator: "\n")
        let plainBody = plain ?? html.map(MailHTML.text(fromHTML:)) ?? ""
        let htmlHeader = fields.map { "<b>\(MailHTML.escape($0.0))：</b>\(MailHTML.escape($0.1))" }.joined(separator: "<br>")
        let htmlBody = html ?? "<div style=\"white-space: pre-wrap\">\(MailHTML.plainTextBody(plain ?? ""))</div>"
        parts.forwarded.append(Forwarded(
            plain: plainHeader + "\n\n" + plainBody,
            html: "<div class=\"kbox-forwarded\"><p>\(htmlHeader)</p>\(htmlBody)</div>",
            hasHTML: html != nil
        ))
        parts.attachments += inner.attachments
        parts.inline += inner.inline
    }

    private static let hiddenTypes: Set<String> = [
        "application/pgp-signature", "application/pkcs7-signature", "application/x-pkcs7-signature",
    ]

    static func collect(_ part: MIMEPart, parentType: String = "", depth: Int = 0, into parts: inout BodyParts) {
        if !part.children.isEmpty {
            if part.type == "multipart/alternative" {
                // Plain from the first alternative that has it (for search), HTML from the richest (last).
                let options = part.children.map { child in
                    var option = BodyParts()
                    collect(child, parentType: part.type, depth: depth, into: &option)
                    return option
                }
                if let option = options.first(where: { !$0.plain.isEmpty }) { parts.plain += option.plain }
                if let option = options.last(where: { !$0.html.isEmpty }) {
                    parts.html += option.html
                    parts.inline += option.inline
                }
                for option in options {
                    parts.attachments += option.attachments
                    parts.forwarded += option.forwarded
                }
            } else {
                for child in part.children { collect(child, parentType: part.type, depth: depth, into: &parts) }
            }
            return
        }

        let disposition = part.disposition
        if part.type == "message/rfc822", disposition != "attachment", depth < 4 {
            forwarded(part, depth: depth, into: &parts)
            return
        }
        let isText = part.type == "text/plain" || part.type == "text/html"
        if isText, disposition != "attachment", part.filename == nil || disposition == "inline" {
            if part.type == "text/plain" { parts.plain.append(part) } else { parts.html.append(part) }
        } else if hiddenTypes.contains(part.type) {
            return
        } else if part.contentID != nil, disposition != "attachment",
                  parentType == "multipart/related" || disposition == "inline" {
            parts.inline.append(part)
        } else {
            parts.attachments.append(part)
        }
    }

    private static func defaultFilename(for type: String) -> String {
        switch type {
        case "message/rfc822": return "邮件.eml"
        case "text/calendar": return "邀请.ics"
        default:
            let ext = UTType(mimeType: type)?.preferredFilenameExtension
            return ext.map { "附件.\($0)" } ?? "附件"
        }
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
