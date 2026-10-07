import Foundation
import Testing

/// Sample messages shared by the mail tests.
enum MailFixtures {
    /// multipart/mixed { alternative { plain (QP), related { html, cid image } }, pdf attachment }
    static let invoice = """
    From: =?UTF-8?B?5byg5LiJ?= <zhang@example.com>
    To: "Li, Si" <li@example.com>, wang@example.com
    Subject: =?UTF-8?B?5Y+R56Wo?=
    Date: Mon, 21 Sep 2026 21:21:13 -0700
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="outer"

    --outer
    Content-Type: multipart/alternative; boundary="alt"

    --alt
    Content-Type: text/plain; charset=utf-8
    Content-Transfer-Encoding: quoted-printable

    Plain caf=C3=A9 body
    --alt
    Content-Type: multipart/related; boundary="rel"

    --rel
    Content-Type: text/html; charset=utf-8

    <html><body><p>HTML <b>body</b></p><img src="cid:logo@x"></body></html>
    --rel
    Content-Type: image/png
    Content-ID: <logo@x>
    Content-Transfer-Encoding: base64

    iVBORw0KGgo=
    --rel--
    --alt--
    --outer
    Content-Type: application/pdf; name="report.pdf"
    Content-Disposition: attachment; filename="report.pdf"
    Content-Transfer-Encoding: base64

    JVBERi0xLjQK
    --outer--

    """

    static let mailbox = """
    From alice@example.com Tue Sep 01 10:00:00 2026
    From: Alice <alice@example.com>
    To: me@example.com
    Subject: First
    Date: Tue, 1 Sep 2026 10:00:00 +0000

    Hello
    From the team, thanks.
    >From here on, quoted.

    From zhang@example.com Mon Sep 21 21:21:13 2026
    \(invoice)
    From bob@example.com Tue Sep 15 10:00:00 2026
    From: Bob <bob@example.com>
    To: me@example.com
    Subject: Second
    Date: Tue, 15 Sep 2026 10:00:00 +0000

    Bye

    """

    static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
