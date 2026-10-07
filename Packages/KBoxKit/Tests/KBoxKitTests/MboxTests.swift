import Foundation
import Testing
@testable import KBoxKit

struct MboxTests {
    @Test func splitsAtEnvelopeLinesOnly() throws {
        let data = Data(MailFixtures.mailbox.utf8)
        let slices = try Mbox.split(data)
        #expect(slices.count == 3)
        #expect(slices[0].envelope == "From alice@example.com Tue Sep 01 10:00:00 2026")
        let first = String(decoding: Mbox.message(slices[0].range, in: data), as: UTF8.self)
        #expect(first.hasPrefix("From: Alice"))
        #expect(first.contains("\nFrom the team"))
        #expect(!first.contains("Subject: =?UTF-8"))
    }

    @Test func undoesMboxrdQuoting() throws {
        let data = Data(MailFixtures.mailbox.utf8)
        let slices = try Mbox.split(data)
        let first = String(decoding: Mbox.message(slices[0].range, in: data), as: UTF8.self)
        #expect(first.contains("\nFrom here on, quoted."))
        #expect(!first.contains(">From"))
    }

    @Test func handlesCRLF() throws {
        let data = Data(MailFixtures.mailbox.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        let slices = try Mbox.split(data)
        #expect(slices.count == 3)
        #expect(slices[2].envelope == "From bob@example.com Tue Sep 15 10:00:00 2026")
        let summary = MailParser.summary(id: 1, slice: slices[1], in: data).0
        #expect(summary.subject == "发票")
        #expect(summary.hasAttachments)
    }

    @Test func treatsAnEmlAsOneMessage() throws {
        let data = Data("Subject: Hi\nFrom: a@b.c\n\nBody\n".utf8)
        #expect(try Mbox.split(data) == [MessageSlice(range: 0..<data.count, envelope: "")])
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: MboxError.notMailbox) { try Mbox.split(Data()) }
        #expect(throws: MboxError.notMailbox) { try Mbox.split(Data("just some text\n".utf8)) }
    }
}
