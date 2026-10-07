import Foundation
import Observation

/// All state of the mail viewer: the open mbox, search and the selected message.
@MainActor @Observable
public final class MailStore {
    public enum Phase: Equatable, Sendable {
        case empty
        case loading(Double)
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .empty
    public private(set) var fileName: String?
    /// Newest first.
    public private(set) var messages: [MailSummary] = []
    /// `messages` filtered by the search.
    public private(set) var results: [MailSummary] = []
    public var searchText = "" {
        didSet { if searchText != oldValue { scheduleSearch() } }
    }
    public var searchScope: MailSearchScope = .all {
        didSet { if searchScope != oldValue { scheduleSearch() } }
    }
    /// Search words as typed, for highlighting.
    public private(set) var searchWords: [String] = []
    public var selectedID: MailSummary.ID? {
        didSet { if selectedID != oldValue { loadSelection() } }
    }
    /// The parsed selected message; may briefly lag behind `selectedID`.
    public private(set) var selected: MailContent?
    /// The page for `selected`; `documentVersion` changes whenever it does.
    public private(set) var document = ""
    public private(set) var documentVersion = 0
    public var allowsRemoteContent = false {
        didSet {
            guard allowsRemoteContent != oldValue, let selected else { return }
            setDocument(MailHTML.document(for: selected, allowRemote: allowsRemoteContent))
        }
    }
    /// Shows the file importer (toolbar button and the empty state share it).
    public var isImporting = false
    /// Bumped to ask the message list to take keyboard focus.
    public private(set) var listFocusRequests = 0

    @ObservationIgnored private var data = Data()
    /// Indexed by message id (file order).
    @ObservationIgnored private var byID: [MailSummary] = []
    @ObservationIgnored private var fields: [SearchFields] = []
    @ObservationIgnored private var accessedURL: URL?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var listFocusRequested = false

    private struct Mailbox: Sendable {
        var data: Data
        var byID: [MailSummary]
        var fields: [SearchFields]
        var newestFirst: [MailSummary]
    }

    public init() {}

    public var selectedSummary: MailSummary? {
        guard let selectedID, byID.indices.contains(selectedID) else { return nil }
        return byID[selectedID]
    }

    /// "1,234 封邮件" / "找到 12 封"
    public var statusLine: String {
        switch phase {
        case .loaded:
            searchWords.isEmpty ? "\(messages.count.formatted()) 封邮件" : "找到 \(results.count.formatted()) 封"
        case .loading: "正在读取…"
        case .empty, .failed: Tool.mail.subtitle
        }
    }

    // MARK: - Opening

    public func open(_ url: URL) {
        close()
        if url.startAccessingSecurityScopedResource() { accessedURL = url }
        fileName = url.pathExtension.lowercased() == "mbox" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        phase = .loading(0)
        let generation = generation
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let store = self else { return }
            let result: Result<Mailbox, any Error>
            do {
                let data = try Mbox.load(url)
                let (byID, fields) = try await Self.index(data) { fraction in
                    await store.reportProgress(fraction, generation: generation)
                }
                let newestFirst = byID.sorted { ($0.date ?? .distantPast, $0.id) > ($1.date ?? .distantPast, $1.id) }
                result = .success(Mailbox(data: data, byID: byID, fields: fields, newestFirst: newestFirst))
            } catch is CancellationError {
                return
            } catch {
                result = .failure(error)
            }
            await store.finishLoading(result, generation: generation)
        }
    }

    public func close() {
        generation += 1
        loadTask?.cancel()
        searchTask?.cancel()
        selectionTask?.cancel()
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        data = Data()
        byID = []
        fields = []
        messages = []
        results = []
        selectedID = nil
        selected = nil
        fileName = nil
        phase = .empty
        try? FileManager.default.removeItem(at: Self.previewFolder)
    }

    /// Splits and summarizes every message, in parallel chunks.
    private nonisolated static func index(
        _ data: Data,
        progress: @Sendable (Double) async -> Void
    ) async throws -> ([MailSummary], [SearchFields]) {
        let slices = try Mbox.split(data)
        let chunkSize = max(64, slices.count / 64 + 1)
        let chunks = stride(from: 0, to: slices.count, by: chunkSize).map { $0..<min($0 + chunkSize, slices.count) }
        var results = [[(MailSummary, SearchFields)]](repeating: [], count: chunks.count)
        try await withThrowingTaskGroup(of: (Int, [(MailSummary, SearchFields)]).self) { group in
            for (number, chunk) in chunks.enumerated() {
                group.addTask {
                    var output: [(MailSummary, SearchFields)] = []
                    output.reserveCapacity(chunk.count)
                    for index in chunk {
                        try Task.checkCancellation()
                        output.append(MailParser.summary(id: index, slice: slices[index], in: data))
                    }
                    return (number, output)
                }
            }
            var done = 0
            for try await (number, output) in group {
                results[number] = output
                done += 1
                await progress(Double(done) / Double(chunks.count))
            }
        }
        let flat = results.joined()
        return (flat.map(\.0), flat.map(\.1))
    }

    private func reportProgress(_ fraction: Double, generation: Int) {
        guard generation == self.generation, case .loading = phase else { return }
        phase = .loading(fraction)
    }

    private func finishLoading(_ result: Result<Mailbox, any Error>, generation: Int) {
        guard generation == self.generation else { return }
        switch result {
        case .success(let mailbox):
            data = mailbox.data
            byID = mailbox.byID
            fields = mailbox.fields
            messages = mailbox.newestFirst
            listFocusRequested = true
            phase = .loaded
            scheduleSearch()
        case .failure(let error):
            accessedURL?.stopAccessingSecurityScopedResource()
            accessedURL = nil
            phase = .failed(error.localizedDescription)
        }
    }

    public func requestListFocus() {
        listFocusRequests += 1
    }

    /// True once after each mailbox opens: the list takes keyboard focus then, so ↓ selects the first message.
    public func takeListFocusRequest() -> Bool {
        defer { listFocusRequested = false }
        return listFocusRequested
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        searchWords = MailSearch.words(searchText)
        let terms = searchWords.map(MailSearch.fold)
        guard !terms.isEmpty else {
            results = messages
            return
        }
        let messages = messages, fields = fields, scope = searchScope
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                messages.filter { MailSearch.matches(fields[$0.id], terms: terms, scope: scope) }
            }.value
            guard !Task.isCancelled else { return }
            self?.results = found
        }
    }

    // MARK: - Selection

    private func loadSelection() {
        selectionTask?.cancel()
        allowsRemoteContent = false
        guard let summary = selectedSummary else {
            selected = nil
            setDocument("")
            return
        }
        let data = data
        selectionTask = Task.detached(priority: .userInitiated) { [weak self] in
            let content = MailParser.content(summary, in: data)
            let document = MailHTML.document(for: content, allowRemote: false)
            guard !Task.isCancelled else { return }
            await self?.show(content, document: document)
        }
    }

    private func show(_ content: MailContent, document: String) {
        guard selectedID == content.summary.id else { return }
        selected = content
        allowsRemoteContent = false
        setDocument(document)
    }

    private func setDocument(_ document: String) {
        self.document = document
        documentVersion += 1
    }

    // MARK: - Attachments

    /// Writes the attachment to a temporary file for Quick Look.
    public func previewURL(for attachment: MailAttachment) throws -> URL {
        let folder = Self.previewFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: Self.safeFilename(attachment.filename))
        try attachment.data.write(to: url)
        return url
    }

    /// Where Quick Look copies go; emptied whenever a mailbox closes.
    private static var previewFolder: URL {
        FileManager.default.temporaryDirectory.appending(path: "kBox-attachments", directoryHint: .isDirectory)
    }

    static func safeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "附件" + cleaned : cleaned
    }
}
