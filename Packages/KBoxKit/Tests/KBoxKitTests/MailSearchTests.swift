import Foundation
import Testing
@testable import KBoxKit

struct MailSearchTests {
    let fields = SearchFields(subject: "Invoice ＡＢＣ", from: "Zoë zoe@example.com", to: "张三 zhang@example.com", body: "Payment due 发票")

    private func matches(_ query: String, _ scope: MailSearchScope = .all) -> Bool {
        MailSearch.matches(fields, terms: MailSearch.words(query).map(MailSearch.fold), scope: scope)
    }

    @Test func foldsCaseAccentsAndWidth() {
        #expect(matches("abc"))
        #expect(matches("ZOE"))
        #expect(matches("发票"))
    }

    @Test func requiresEveryWord() {
        #expect(matches("invoice payment"))
        #expect(!matches("invoice refund"))
    }

    @Test func respectsScope() {
        #expect(matches("invoice", .subject))
        #expect(!matches("payment", .subject))
        #expect(matches("zoe", .from))
        #expect(!matches("zoe", .to))
        #expect(matches("张三", .to))
        #expect(matches("due", .body))
        #expect(!matches("invoice", .body))
    }

    @Test func containsFallsBackForBridgedStrings() {
        let bridged = NSString(string: "hello world") as String
        #expect(MailSearch.contains(bridged, "o w"))
        #expect(!MailSearch.contains("short", "longer needle"))
        #expect(MailSearch.contains("anything", ""))
    }
}

struct MailHTMLTests {
    @Test func extractsVisibleText() {
        let html = """
        <html><head><style>p { color: red }</style><title>T</title></head>
        <body><!-- note --><p>Hi&nbsp;there &amp; &#20320;&#x597D;</p><script>run()</script>a < b</body></html>
        """
        let text = MailHTML.text(fromHTML: html)
        #expect(text.contains("Hi there & 你好"))
        #expect(text.contains("a < b"))
        #expect(!text.contains("color"))
        #expect(!text.contains("run()"))
        #expect(!text.contains("note"))
    }

    @Test func blocksRemoteContentUnlessAllowed() {
        let blocked = MailHTML.document(html: "<p>x</p>", allowRemote: false)
        #expect(blocked.hasPrefix(#"<meta http-equiv="Content-Security-Policy""#))
        #expect(blocked.contains("default-src 'none'; img-src data:"))
        #expect(blocked.contains(#"<meta http-equiv="x-dns-prefetch-control" content="off">"#))
        let allowed = MailHTML.document(html: "<!DOCTYPE html><html><p>x</p></html>", allowRemote: true)
        #expect(allowed.hasPrefix("<!DOCTYPE html><meta"))
        #expect(allowed.contains("default-src * data:"))
        #expect(allowed.contains("script-src 'none'"))
    }

    @Test func quotesAndEscapesPlainText() {
        #expect(MailHTML.plainTextBody("Hi <b>\n> quoted\n>> deeper\nback")
            == "Hi &lt;b&gt;<blockquote>quoted<blockquote>deeper</blockquote></blockquote>back")
        #expect(MailHTML.plainTextBody("see https://example.com/a?b=1&c=2 now")
            == #"see <a href="https://example.com/a?b=1&amp;c=2">https://example.com/a?b=1&amp;c=2</a> now"#)
    }

    @Test func detectsRemoteReferences() {
        #expect(MailHTML.hasRemoteReferences(#"<img src="https://example.com/a.png">"#))
        #expect(MailHTML.hasRemoteReferences(#"<td style="background: url('http://example.com/b.png')">"#))
        #expect(!MailHTML.hasRemoteReferences(#"<a href="https://example.com">link</a> http://example.com"#))
        #expect(!MailHTML.hasRemoteReferences(#"<img src="data:image/png;base64,AAAA">"#))
    }
}

struct MailDateFormatTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func listDatesLikeMail() {
        let now = MailFixtures.utc(2026, 9, 21, 12) // Monday
        #expect(Fmt.mailListDate(MailFixtures.utc(2026, 9, 21, 9, 5), now: now, calendar: calendar) == "09:05")
        #expect(Fmt.mailListDate(MailFixtures.utc(2026, 9, 20, 23), now: now, calendar: calendar) == "昨天")
        #expect(Fmt.mailListDate(MailFixtures.utc(2026, 9, 17, 8), now: now, calendar: calendar) == "星期四")
        #expect(Fmt.mailListDate(MailFixtures.utc(2026, 9, 1), now: now, calendar: calendar) == "2026/9/1")
        #expect(Fmt.mailListDate(nil, now: now, calendar: calendar) == "")
    }

    @Test func fullDate() {
        #expect(Fmt.mailFullDate(MailFixtures.utc(2026, 9, 21, 9, 5), calendar: calendar) == "2026年9月21日 星期一 09:05")
    }
}
