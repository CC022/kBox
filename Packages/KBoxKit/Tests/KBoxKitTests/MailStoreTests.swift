import Foundation
import Testing
@testable import KBoxKit

@MainActor
struct MailStoreTests {
    private func openSample() async throws -> (MailStore, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "kbox-test-\(UUID().uuidString).mbox")
        try Data(MailFixtures.mailbox.utf8).write(to: url)
        let store = MailStore()
        store.open(url)
        try await waitUntil { store.phase == .loaded }
        return (store, url)
    }

    @Test func opensNewestFirst() async throws {
        let (store, url) = try await openSample()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(store.fileName == url.deletingPathExtension().lastPathComponent)
        #expect(store.messages.map(\.subject) == ["发票", "Second", "First"])
        #expect(store.results.map(\.id) == store.messages.map(\.id))
        #expect(store.statusLine == "3 封邮件")
    }

    @Test func searches() async throws {
        let (store, url) = try await openSample()
        defer { try? FileManager.default.removeItem(at: url) }

        store.searchText = "CAFÉ"
        try await waitUntil { store.results.count == 1 }
        #expect(store.results.first?.subject == "发票")
        #expect(store.statusLine == "找到 1 封")

        store.searchText = "bob"
        store.searchScope = .from
        try await waitUntil { store.results.map(\.subject) == ["Second"] }

        store.searchScope = .subject
        try await waitUntil { store.results.isEmpty }

        store.searchText = ""
        #expect(store.results.count == 3)
    }

    @Test func selectsAndBuildsTheDocument() async throws {
        let (store, url) = try await openSample()
        defer { try? FileManager.default.removeItem(at: url) }

        store.selectedID = store.messages[0].id
        try await waitUntil { store.selected != nil }
        #expect(store.selected?.attachments.map(\.filename) == ["report.pdf"])
        #expect(store.document.contains("img-src data:"))

        let version = store.documentVersion
        store.allowsRemoteContent = true
        #expect(store.documentVersion == version + 1)
        #expect(store.document.contains("default-src *"))

        store.selectedID = store.messages[1].id
        try await waitUntil { store.selected?.summary.subject == "Second" }
        #expect(!store.allowsRemoteContent)
        #expect(store.document.contains("Bye"))
    }

    @Test func reportsFilesThatAreNotMailboxes() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kbox-test-\(UUID().uuidString).txt")
        try Data("just text\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MailStore()
        store.open(url)
        try await waitUntil { if case .failed = store.phase { true } else { false } }
        #expect(store.phase == .failed("这不是 mbox 邮箱文件"))
    }

    @Test func cancelsLoading() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kbox-test-\(UUID().uuidString).mbox")
        try Data(MailFixtures.mailbox.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MailStore()
        store.open(url)
        store.close()
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.phase == .empty)
        #expect(store.messages.isEmpty)
        #expect(store.fileName == nil)
    }

    @Test func recoversAfterAFailedOpen() async throws {
        let bad = FileManager.default.temporaryDirectory.appending(path: "kbox-test-\(UUID().uuidString).txt")
        try Data("just text\n".utf8).write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        let store = MailStore()
        store.open(bad)
        try await waitUntil { if case .failed = store.phase { true } else { false } }
        store.close()
        #expect(store.phase == .empty)

        let (good, url) = try await openSample()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(good.messages.count == 3)
        #expect(good.takeListFocusRequest())
        #expect(!good.takeListFocusRequest())
    }

    @Test func writesPreviewFiles() throws {
        let store = MailStore()
        let url = try store.previewURL(for: MailAttachment(id: 0, filename: "a/b.txt", mimeType: "text/plain", data: Data("hi".utf8)))
        #expect(url.lastPathComponent == "a_b.txt")
        #expect(try Data(contentsOf: url) == Data("hi".utf8))
    }
}
