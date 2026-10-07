import SwiftUI

/// The message list (its own column on iPadOS), or the open / loading / error state before there is one.
struct MessageListView: View {
    @Bindable var store: MailStore
    /// Clicking a row selects it without moving keyboard focus off the sidebar (or the message body),
    /// so ↑/↓ would go there. Take focus explicitly whenever the selection changes, and once after a
    /// mailbox opens — but not when the list merely reappears because the sidebar switched tools.
    @FocusState private var isListFocused: Bool

    var body: some View {
        Group {
            if store.phase == .loaded {
                list
            } else {
                MailboxStateView(store: store)
            }
        }
        #if os(iOS)
        .mailChrome(store: store)
        .navigationTitle(store.fileName ?? Tool.mail.title)
        .navigationSubtitle(store.statusLine)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var list: some View {
        List(store.results, selection: $store.selectedID) { message in
            MessageRow(message: message, words: store.searchWords)
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.plain)
        #endif
        .focused($isListFocused)
        .onAppear {
            if store.takeListFocusRequest() { isListFocused = true }
        }
        .onChange(of: store.selectedID) {
            if store.selectedID != nil { isListFocused = true }
        }
        .onChange(of: store.listFocusRequests) { isListFocused = true }
        .overlay {
            if store.results.isEmpty && !store.searchWords.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            }
        }
    }
}

private struct MessageRow: View {
    let message: MailSummary
    let words: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(highlighted(message.from?.displayName ?? "（无发件人）"))
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if message.hasAttachments {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("有附件")
                }
                Text(Fmt.mailListDate(message.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(highlighted(message.subject.isEmpty ? "（无主题）" : message.subject))
                .font(.callout)
                .lineLimit(1)
            // Two lines even for a short snippet, so every row is the same height as in Mail.
            Text(highlighted(message.snippet))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(.vertical, 4)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        for word in words {
            var searchStart = text.startIndex
            while let range = text.range(of: word, options: MailSearch.foldingOptions, range: searchStart..<text.endIndex),
                  !range.isEmpty {
                if let attributed = Range(range, in: result) {
                    result[attributed].backgroundColor = Color.yellow.opacity(0.45)
                }
                searchStart = range.upperBound
            }
        }
        return result
    }
}

/// Nothing open, reading, or failed.
struct MailboxStateView: View {
    let store: MailStore

    var body: some View {
        switch store.phase {
        case .empty, .loaded:
            ContentUnavailableView {
                Label("打开 mbox 文件", systemImage: "envelope.open")
            } description: {
                Text(dropHint)
            } actions: {
                Button("打开…") { store.isImporting = true }
                    .buttonStyle(.borderedProminent)
            }
        case .loading(let fraction):
            VStack(spacing: 12) {
                ProgressView(value: fraction)
                    .frame(maxWidth: 260)
                Text("正在读取「\(store.fileName ?? "")」…")
                    .foregroundStyle(.secondary)
                Button("取消") { store.close() }
                    .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("无法打开", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("打开其他文件…") { store.isImporting = true }
            }
        }
    }

    private var dropHint: String {
        #if os(macOS)
        "支持 Gmail（Google Takeout）、Thunderbird、Apple Mail 导出的邮箱，也可以把文件拖到这里。"
        #else
        "支持 Gmail（Google Takeout）、Thunderbird、Apple Mail 导出的邮箱。"
        #endif
    }
}
