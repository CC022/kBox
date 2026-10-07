import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// macOS: message list on the left, reader on the right, draggable divider between.
struct MailboxView: View {
    @Bindable var store: MailStore

    var body: some View {
        Group {
            if store.phase == .loaded {
                // HSplitView sizes itself to its panes' ideal height, so both must ask for all of it;
                // otherwise, with no message selected, the split shrinks to a strip in the middle.
                HSplitView {
                    MessageListView(store: store)
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 480, maxHeight: .infinity)
                    MessageDetailView(store: store)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                MailboxStateView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            store.open(url)
            return true
        }
        .mailChrome(store: store)
        .navigationTitle(store.fileName ?? Tool.mail.title)
        .navigationSubtitle(store.statusLine)
    }
}
#endif

extension View {
    /// 打开…（⌘O）, the file importer and the mail search (⌘F). On the split view on macOS,
    /// on the list column on iPadOS.
    func mailChrome(store: MailStore) -> some View {
        modifier(MailChrome(store: store))
    }
}

private struct MailChrome: ViewModifier {
    @Bindable var store: MailStore
    @FocusState private var isSearchFocused: Bool

    /// `.mbox` has no system type (it is plain data); Thunderbird mailboxes have no extension at all;
    /// Apple Mail exports a folder.
    private static let types: [UTType] = [.data, .folder] + [UTType("com.apple.mail.mbox")].compactMap { $0 }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.isImporting = true
                    } label: {
                        Label("打开", systemImage: "folder")
                    }
                    .help("打开 mbox 文件（⌘O）")
                    .keyboardShortcut("o")
                }
            }
            .fileImporter(isPresented: $store.isImporting, allowedContentTypes: Self.types) { result in
                if case .success(let url) = result { store.open(url) }
            }
            .searchable(text: $store.searchText, placement: searchPlacement, prompt: "搜索邮件")
            .searchScopes($store.searchScope) {
                ForEach(MailSearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .searchFocused($isSearchFocused)
            // Return, or Escape out of the field, would leave focus nowhere; give it to the list so ↑/↓ work.
            .onSubmit(of: .search) { store.requestListFocus() }
            .onChange(of: isSearchFocused) {
                guard !isSearchFocused else { return }
                #if os(macOS)
                Task { @MainActor in
                    if let window = NSApp.keyWindow, window.firstResponder === window { store.requestListFocus() }
                }
                #endif
            }
            .task {
                if DebugOverrides.focusMailSearch { isSearchFocused = true }
            }
            .background {
                Button("搜索邮件") { isSearchFocused = true }
                    .keyboardShortcut("f")
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    private var searchPlacement: SearchFieldPlacement {
        #if os(macOS)
        .toolbar
        #else
        .automatic
        #endif
    }
}
