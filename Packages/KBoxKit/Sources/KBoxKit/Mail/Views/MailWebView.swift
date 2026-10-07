import SwiftUI
import WebKit

/// Message body in a WKWebView. Page scripts are off and the page's own policy blocks the network
/// (see `MailHTML.document`); links open outside, and search words are marked in the text.
@MainActor
struct MailWebView {
    let html: String
    /// Reloads only when this changes, so large pages are not compared on every update.
    let version: Int
    let highlight: [String]

    @Environment(\.openURL) private var openURL

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        #if os(macOS)
        // Let plain-text mail sit on the window background in dark mode.
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    private func update(_ webView: WKWebView, _ coordinator: Coordinator) {
        coordinator.openURL = openURL
        if coordinator.version != version {
            coordinator.version = version
            coordinator.highlight = highlight
            webView.loadHTMLString(html, baseURL: nil)
        } else if coordinator.highlight != highlight {
            coordinator.highlight = highlight
            coordinator.applyHighlight(in: webView, scroll: true)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var version = -1
        var highlight: [String] = []
        var openURL: OpenURLAction?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if action.navigationType == .linkActivated {
                openOutside(url)
                return .cancel
            }
            // Only the page we loaded ourselves; no meta refreshes, frames or form posts.
            return url.scheme == "about" && action.targetFrame?.isMainFrame != false ? .allow : .cancel
        }

        /// `target="_blank"` links.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { openOutside(url) }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyHighlight(in: webView, scroll: true)
        }

        private func openOutside(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) else { return }
            openURL?(url)
        }

        /// Wraps the words in `<mark>`. Runs in the app's own script world, which is unaffected by the
        /// page having JavaScript turned off.
        func applyHighlight(in webView: WKWebView, scroll: Bool) {
            let words = highlight
            Task {
                _ = try? await webView.callAsyncJavaScript(
                    Self.highlightScript,
                    arguments: ["words": words, "scroll": scroll],
                    in: nil,
                    contentWorld: .defaultClient
                )
            }
        }

        private static let highlightScript = """
        for (const mark of document.querySelectorAll('mark[data-kbox]')) { mark.replaceWith(...mark.childNodes); }
        document.body && document.body.normalize();
        const needles = words.map(w => w.toLocaleLowerCase()).filter(w => w.length > 0);
        if (!needles.length || !document.body) { return; }
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: n => n.parentElement && !['SCRIPT', 'STYLE', 'TITLE'].includes(n.parentElement.tagName)
                ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT
        });
        const nodes = [];
        while (walker.nextNode()) { nodes.push(walker.currentNode); }
        for (const node of nodes) {
            const text = node.nodeValue;
            const lower = text.toLocaleLowerCase();
            if (lower.length !== text.length) { continue; }
            const ranges = [];
            for (const needle of needles) {
                let i = lower.indexOf(needle);
                while (i !== -1) { ranges.push([i, i + needle.length]); i = lower.indexOf(needle, i + needle.length); }
            }
            if (!ranges.length) { continue; }
            ranges.sort((a, b) => a[0] - b[0]);
            const merged = [];
            for (const r of ranges) {
                const last = merged[merged.length - 1];
                if (last && r[0] <= last[1]) { last[1] = Math.max(last[1], r[1]); } else { merged.push(r.slice()); }
            }
            const fragment = document.createDocumentFragment();
            let cursor = 0;
            for (const [start, end] of merged) {
                fragment.append(text.slice(cursor, start));
                const mark = document.createElement('mark');
                mark.dataset.kbox = '1';
                mark.textContent = text.slice(start, end);
                fragment.append(mark);
                cursor = end;
            }
            fragment.append(text.slice(cursor));
            node.replaceWith(fragment);
        }
        const first = document.querySelector('mark[data-kbox]');
        if (scroll && first) { first.scrollIntoView({ block: 'center' }); }
        """
    }
}

#if os(macOS)
extension MailWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(webView, context.coordinator) }
}
#else
extension MailWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(webView, context.coordinator) }
}
#endif
