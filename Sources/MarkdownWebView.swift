import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int
    @ObservedObject var state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // let the dark window show through
        webView.navigationDelegate = context.coordinator
        load(into: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let signature = "\(url.path)#\(reloadToken)"
        if context.coordinator.loadedSignature != signature {
            load(into: webView, context: context)
        }
        context.coordinator.updateSearch(in: webView)
    }

    private func load(into webView: WKWebView, context: Context) {
        context.coordinator.loadedSignature = "\(url.path)#\(reloadToken)"
        context.coordinator.documentReady = false
        context.coordinator.lastSearch = nil
        context.coordinator.initialNavigationPending = true
        let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? "*Could not read file.*"
        let html = HTMLTemplate.render(markdown: markdown)
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: AppState
        var loadedSignature: String?
        var documentReady = false
        var lastSearch: SearchRequest?
        private var searchRevision = 0
        private var wasShowingSearch = false
        var initialNavigationPending = true
        private let openExternalURL: (URL) -> Void

        struct SearchRequest: Equatable {
            let query: String
            let index: Int
            let visible: Bool
        }

        init(state: AppState, openExternalURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
            self.state = state
            self.openExternalURL = openExternalURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            documentReady = true
            updateSearch(in: webView)
        }

        func updateSearch(in webView: WKWebView) {
            if wasShowingSearch && !state.showingSearch {
                webView.window?.makeFirstResponder(webView)
            }
            wasShowingSearch = state.showingSearch
            guard documentReady else { return }
            let request = SearchRequest(query: state.showingSearch ? state.searchQuery : "",
                                        index: state.searchIndex, visible: state.showingSearch)
            guard lastSearch != request else { return }
            lastSearch = request
            searchRevision += 1
            let revision = searchRevision
            let signature = loadedSignature
            webView.callAsyncJavaScript(
                "return window.mdpSearch(query, index);",
                arguments: ["query": request.query, "index": request.index],
                in: nil, in: .page
            ) { [weak self] result in
                guard let self, self.searchRevision == revision,
                      self.loadedSignature == signature,
                      self.state.showingSearch == request.visible,
                      !request.visible || (self.state.searchQuery == request.query &&
                                            self.state.searchIndex == request.index) else { return }
                guard case .success(let value) = result,
                      let values = value as? [String: Any],
                      let count = values["count"] as? Int,
                      let index = values["index"] as? Int else { return }
                if request.visible {
                    self.state.searchCount = count
                    self.state.searchIndex = index
                    self.state.searchResultQuery = request.query
                }
            }
        }

        private func withoutFragment(_ url: URL) -> URL? {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            components?.fragment = nil
            return components?.url
        }

        private func isDocumentFragment(_ url: URL, in webView: WKWebView) -> Bool {
            guard url.fragment != nil, let destination = withoutFragment(url) else { return false }
            return [webView.url, state.currentURL, state.currentURL?.deletingLastPathComponent()]
                .compactMap { $0 }.contains { withoutFragment($0) == destination }
        }

        // Keep document fragments in the viewer and send only user-activated
        // external links to macOS. Document content cannot replace the preview.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let link = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if initialNavigationPending, navigationAction.navigationType == .other,
               navigationAction.targetFrame?.isMainFrame == true,
               link.absoluteString == "about:blank" || link == state.currentURL?.deletingLastPathComponent() {
                initialNavigationPending = false
                decisionHandler(.allow)
                return
            }
            if isDocumentFragment(link, in: webView) {
                let fragment = link.fragment?.removingPercentEncoding ?? link.fragment ?? ""
                webView.callAsyncJavaScript("""
                    if (!fragment) { window.scrollTo(0, 0); return; }
                    const target = document.getElementById(fragment) || document.getElementsByName(fragment)[0];
                    if (target) target.scrollIntoView({block: 'start'});
                    """, arguments: ["fragment": fragment], in: nil, in: .page)
            } else if navigationAction.navigationType == .linkActivated,
                      ["http", "https", "mailto", "file"].contains(link.scheme?.lowercased() ?? "") {
                openExternalURL(link)
            }
            decisionHandler(.cancel)
        }
    }
}
