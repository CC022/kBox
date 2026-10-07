import Foundation
import Testing
@testable import KBoxKit

struct MIMETests {
    @Test func decodesEncodedWords() {
        #expect(MIME.decodeWords("=?UTF-8?B?5L2g5aW9?=") == "你好")
        #expect(MIME.decodeWords("=?gb2312?B?xOO6ww==?=") == "你好")
        #expect(MIME.decodeWords("=?ISO-8859-1?Q?Caf=E9_au_lait?=") == "Café au lait")
        #expect(MIME.decodeWords("Re: =?UTF-8?B?5L2g5aW9?= world") == "Re: 你好 world")
        #expect(MIME.decodeWords("plain =? text") == "plain =? text")
    }

    @Test func joinsAdjacentEncodedWords() {
        #expect(MIME.decodeWords("=?UTF-8?B?5L2g?= =?UTF-8?B?5aW9?=") == "你好")
        // 你 split across two words
        #expect(MIME.decodeWords("=?UTF-8?B?5L0=?=\r\n =?UTF-8?B?oOWlvQ==?=") == "你好")
    }

    @Test func decodesRawEightBitHeaders() {
        var data = Data("Subject: ".utf8)
        data.append(contentsOf: [0xC4, 0xE3, 0xBA, 0xC3]) // 你好 in GBK
        data.append(Data("\nContent-Type: text/plain; charset=gbk\n\nbody".utf8))
        let (headers, body) = MIME.parseHeaders(data)
        #expect(headers["subject"] == "你好")
        #expect(String(decoding: body, as: UTF8.self) == "body")
    }

    @Test func unfoldsHeaders() {
        let (headers, _) = MIME.parseHeaders(Data("Subject: one\r\n two\r\nX-A: b\r\n\r\n".utf8))
        #expect(headers["subject"] == "one two")
        #expect(headers["x-a"] == "b")
    }

    @Test func decodesTransferEncodings() {
        #expect(String(decoding: MIME.decodeQuotedPrintable(Data("caf=C3=A9 =\nnext=\r\nline".utf8)), as: UTF8.self) == "café nextline")
        #expect(String(decoding: MIME.decodeBase64(Data("SGk".utf8)), as: UTF8.self) == "Hi")
        #expect(String(decoding: MIME.decodeBase64(Data("5L2g\n5aW9\n".utf8)), as: UTF8.self) == "你好")
    }

    @Test func parsesParametersAndRFC2231() {
        let type = MIME.parameterized(#"Text/Plain; charset="gb2312"; format=flowed"#)
        #expect(type.value == "text/plain")
        #expect(type.params == ["charset": "gb2312", "format": "flowed"])
        #expect(MIME.parameterized("attachment; filename*=UTF-8''%E4%BD%A0%E5%A5%BD.txt").params["filename"] == "你好.txt")
        #expect(MIME.parameterized("attachment; filename*0*=UTF-8''%E4%BD%A0; filename*1*=%E5%A5%BD.txt").params["filename"] == "你好.txt")
        #expect(MIME.parameterized(#"attachment; filename="a \"b\".txt""#).params["filename"] == #"a "b".txt"#)
    }

    @Test func acceptsSpaceBeforeColon() {
        let (headers, body) = MIME.parseHeaders(Data("Subject : Hi\nFrom: a@b.c\n\nbody".utf8))
        #expect(headers["subject"] == "Hi")
        #expect(headers["from"] == "a@b.c")
        #expect(String(decoding: body, as: UTF8.self) == "body")
    }

    @Test func stripsPathsFromFilenames() {
        func filename(_ disposition: String) -> String? {
            MIMEPart.parse(Data("Content-Type: application/octet-stream\nContent-Disposition: \(disposition)\n\nx".utf8)).filename
        }
        #expect(filename(#"attachment; filename="C:\fakepath\report.doc""#) == "report.doc")
        #expect(filename(#"attachment; filename="../../etc/passwd""#) == "passwd")
        #expect(filename(#"attachment; filename="..""#) == nil)
        #expect(filename(#"attachment; filename="a \"b\".txt""#) == #"a "b".txt"#)
    }

    @Test func handlesCharsetAliasesAndMislabels() {
        #expect(MIME.encoding(forCharset: "_iso-2022-jp$esc") == MIME.encoding(forCharset: "iso-2022-jp"))
        #expect(MIME.encoding(forCharset: "GB_2312-80") == MIME.gb18030)
        #expect(MIME.encoding(forCharset: " \"UTF-8\" ") == .utf8)
        #expect(MIME.decode(Data("café 你好".utf8), charset: "iso-8859-1") == "café 你好")
        #expect(MIME.decode(Data([0x63, 0x61, 0x66, 0xE9]), charset: "iso-8859-1") == "café")
        #expect(MIME.decode(Data([0xC4, 0xE3, 0xBA, 0xC3]), charset: "x-unknown") == "你好")
    }

    @Test func sniffsHTMLCharset() {
        var data = Data("Content-Type: text/html\n\n<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=gb2312\"></head><body>".utf8)
        data.append(contentsOf: [0xC4, 0xE3, 0xBA, 0xC3])
        data.append(Data("</body></html>".utf8))
        #expect(MIMEPart.parse(data).text.contains("<body>你好</body>"))
    }

    @Test func unflowsFormatFlowed() {
        #expect(MailParser.unflow("Hello \nworld\n> quoted \n> more\n-- \nsig", deleteSpace: false)
            == "Hello world\n> quoted more\n-- \nsig")
        #expect(MailParser.unflow("abc \ndef", deleteSpace: true) == "abcdef")
        let message = Data("Content-Type: text/plain; charset=utf-8; format=flowed\n\nOne long \nline.\n".utf8)
        let summary = MailParser.summary(id: 0, slice: MessageSlice(range: 0..<message.count, envelope: ""), in: message).0
        #expect(summary.snippet == "One long line.")
        #expect(MailParser.content(summary, in: message).plainText == "One long line.\n")
    }

    @Test func rendersInlineForwardedMessages() {
        let message = """
        Subject: Fwd: Inner subject
        Content-Type: multipart/mixed; boundary="b"

        --b
        Content-Type: text/plain

        See below.
        --b
        Content-Type: message/rfc822

        From: Inner Sender <inner@example.com>
        Subject: Inner subject
        Date: Tue, 22 Sep 2026 04:21:13 +0000
        Content-Type: multipart/mixed; boundary="i"

        --i
        Content-Type: text/html

        <p>Inner body</p>
        --i
        Content-Type: application/pdf; name="inner.pdf"

        JVBERi0xLjQK
        --i--
        --b
        Content-Type: message/rfc822
        Content-Disposition: attachment

        Subject: Attached

        Attached body
        --b--
        """
        let data = Data(message.utf8)
        let summary = MailParser.summary(id: 0, slice: MessageSlice(range: 0..<data.count, envelope: ""), in: data).0
        let content = MailParser.content(summary, in: data)
        let plain = content.plainText ?? ""
        #expect(plain.hasPrefix("See below."))
        #expect(plain.contains("转发的邮件"))
        #expect(plain.contains("发件人：Inner Sender <inner@example.com>"))
        #expect(plain.contains("主题：Inner subject"))
        #expect(plain.contains("Inner body"))
        #expect(content.html == nil)
        #expect(content.attachments.map(\.filename) == ["inner.pdf", "邮件.eml"])
        #expect(summary.snippet.contains("Inner body"))
    }

    @Test func rendersDigestsInline() {
        let message = """
        Content-Type: multipart/digest; boundary="d"

        --d

        Subject: First post

        Hello one
        --d

        Subject: Second post
        Content-Type: text/html

        <b>Hello two</b>
        --d--
        """
        let data = Data(message.utf8)
        let summary = MailParser.summary(id: 0, slice: MessageSlice(range: 0..<data.count, envelope: ""), in: data).0
        let content = MailParser.content(summary, in: data)
        let html = content.html ?? ""
        #expect(html.contains("主题：</b>First post"))
        #expect(html.contains("<b>Hello two</b>"))
        #expect(content.attachments.isEmpty)
    }

    @Test func ignoresLongerBoundaries() {
        let body = Data("--b\nA\n--bb\nnot a part\n--b\nB\n--b--\n".utf8)
        let parts = MIME.splitMultipart(body, boundary: "b").map { String(decoding: $0, as: UTF8.self) }
        #expect(parts == ["A\n--bb\nnot a part", "B"])
    }

    @Test func summarizesMultipartMessage() throws {
        let data = Data(MailFixtures.invoice.utf8)
        let (summary, fields) = MailParser.summary(id: 0, slice: MessageSlice(range: 0..<data.count, envelope: ""), in: data)
        #expect(summary.subject == "发票")
        #expect(summary.from == MailAddress(name: "张三", email: "zhang@example.com"))
        #expect(summary.to == [MailAddress(name: "Li, Si", email: "li@example.com"), MailAddress(name: "", email: "wang@example.com")])
        #expect(summary.date == MailFixtures.utc(2026, 9, 22, 4, 21, 13))
        #expect(summary.snippet == "Plain café body")
        #expect(summary.hasAttachments)
        #expect(fields.body == "plain cafe body")
    }

    @Test func inlinesCidImagesAndListsAttachments() throws {
        let data = Data(MailFixtures.invoice.utf8)
        let summary = MailParser.summary(id: 0, slice: MessageSlice(range: 0..<data.count, envelope: ""), in: data).0
        let content = MailParser.content(summary, in: data)
        let html = try #require(content.html)
        #expect(html.contains(#"<img src="data:image/png;base64,iVBORw0KGgo=">"#))
        #expect(!html.contains("cid:"))
        #expect(content.plainText == "Plain café body")
        #expect(content.attachments.map(\.filename) == ["report.pdf"])
        #expect(content.attachments.first?.data == Data("%PDF-1.4\n".utf8))
        #expect(content.attachments.first?.contentType == .pdf)
        #expect(!content.hasRemoteContent)
    }

    @Test func fallsBackToHTMLTextAndEnvelopeDate() {
        let message = """
        Subject: News
        Content-Type: text/html; charset=utf-8

        <p>Hello&nbsp;<b>world</b></p>
        """
        let data = Data(message.utf8)
        let slice = MessageSlice(range: 0..<data.count, envelope: "From - Mon Sep 21 21:21:13 2026")
        let summary = MailParser.summary(id: 0, slice: slice, in: data).0
        #expect(summary.snippet == "Hello world")
        #expect(summary.date == MailFixtures.utc(2026, 9, 21, 21, 21, 13))
        #expect(!summary.hasAttachments)
    }
}

struct MailAddressTests {
    @Test func parsesAddressLists() {
        let list = MailAddress.parseList(#""Li, Si" <li@example.com>, wang@example.com, =?UTF-8?B?5byg5LiJ?= <zhang@example.com>"#)
        #expect(list == [
            MailAddress(name: "Li, Si", email: "li@example.com"),
            MailAddress(name: "", email: "wang@example.com"),
            MailAddress(name: "张三", email: "zhang@example.com"),
        ])
        #expect(MailAddress.parseList("undisclosed-recipients:;").isEmpty)
        #expect(MailAddress.parseList("zhang@example.com (张三)") == [MailAddress(name: "张三", email: "zhang@example.com")])
        #expect(MailAddress.parseList("Team: a@b.c, d@e.f;").map(\.email) == ["a@b.c", "d@e.f"])
        #expect(MailAddress.parseList("=?UTF-8?Q?Doe,_John?= <j@x.com>, b@y.com") == [
            MailAddress(name: "Doe, John", email: "j@x.com"),
            MailAddress(name: "", email: "b@y.com"),
        ])
    }

    @Test func initials() {
        #expect(MailAddress(name: "张三", email: "").initials == "张")
        #expect(MailAddress(name: "John Appleseed", email: "").initials == "JA")
        #expect(MailAddress(name: "", email: "zhang@example.com").initials == "Z")
    }
}

struct MailDateTests {
    @Test func parsesCommonForms() {
        let expected = MailFixtures.utc(2026, 9, 22, 4, 21, 13)
        #expect(MailDate.parse("Mon, 21 Sep 2026 21:21:13 -0700") == expected)
        #expect(MailDate.parse("Mon, 21 Sep 2026 21:21:13 -0700 (PDT)") == expected)
        #expect(MailDate.parse("21 Sep 2026 21:21:13 PDT") == expected)
        #expect(MailDate.parse("Tue, 22 Sep 2026 12:21:13 +0800") == expected)
        #expect(MailDate.parse("Tue, 22 Sep 2026 04:21:13 GMT") == expected)
        #expect(MailDate.parse("Tue, 22 Sep 26 04:21 +0000") == MailFixtures.utc(2026, 9, 22, 4, 21))
        #expect(MailDate.parse("not a date") == nil)
        #expect(MailDate.parse("Tue, 22 Sep 2026 12:21:13 +08:00") == expected)
        #expect(MailDate.parse("Tue, 22 Sep 2026 12:21:13 GMT+08:00") == expected)
        #expect(MailDate.parse("Tue, 22 Sep 2026 12:21:13 GMT+8") == expected)
        #expect(MailDate.parse("Mon, 21 Sep 2026 23:21:13 -05:00") == expected)
    }

    @Test func fallsBackToReceived() {
        let expected = MailFixtures.utc(2026, 9, 22, 4, 21, 13)
        #expect(MailDate.parseReceived("from mx.example.com by mail.example.com; Tue, 22 Sep 2026 04:21:13 +0000 (UTC)") == expected)
        let message = Data("""
        Received: from a by b; Tue, 22 Sep 2026 04:21:13 +0000
        Received: from c by d; Mon, 21 Sep 2026 00:00:00 +0000
        Date: sometime last week
        Subject: x

        body
        """.utf8)
        let slice = MessageSlice(range: 0..<message.count, envelope: "From - Mon Jan 01 00:00:00 2001")
        #expect(MailParser.summary(id: 0, slice: slice, in: message).0.date == expected)
    }

    @Test func parsesEnvelopes() {
        #expect(MailDate.parseEnvelope("From - Mon Sep 21 21:21:13 2026") == MailFixtures.utc(2026, 9, 21, 21, 21, 13))
        #expect(MailDate.parseEnvelope("From 1712@xxx Wed Jan 01 12:00:00 +0000 2025") == MailFixtures.utc(2025, 1, 1, 12))
        #expect(MailDate.parseEnvelope("") == nil)
    }
}
