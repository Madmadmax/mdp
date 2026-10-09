import AppKit
import WebKit
import SwiftUI

@main
struct SearchTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func wait(_ description: String, until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 15)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        expect(condition(), "Timed out: \(description)")
    }

    static func key(_ code: UInt16, _ characters: String,
                    modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    static func main() {
        _ = NSApplication.shared
        let state = AppState(url: URL(fileURLWithPath: "/private/tmp/search-fixture.md"))
        expect(state.handleKey(key(3, "а", modifiers: .command)) == nil && state.showingSearch,
               "Cmd+F must open search in Cyrillic layout")
        state.searchQuery = "hello"
        state.searchCount = 3
        expect(state.handleKey(key(36, "\r")) == nil && state.searchIndex == 1, "Enter advances")
        _ = state.handleKey(key(36, "\r", modifiers: .shift))
        expect(state.searchIndex == 0, "Shift+Enter goes backwards")
        _ = state.handleKey(key(36, "\r", modifiers: .shift))
        expect(state.searchIndex == 2, "Previous wraps")
        _ = state.handleKey(key(3, "f", modifiers: .command))
        expect(!state.showingSearch && !state.showingList, "Repeated Cmd+F closes search")
        _ = state.handleKey(key(3, "α", modifiers: [.command, .capsLock]))
        _ = state.handleKey(key(53, ""))
        expect(!state.showingSearch && !state.showingList, "First Esc only closes search")
        _ = state.handleKey(key(53, ""))
        expect(state.showingList, "Next Esc opens the file list")
        _ = state.handleKey(key(3, "f", modifiers: .command))
        expect(state.showingSearch && !state.showingList, "Search replaces the file list")
        state.searchQuery = "different"
        expect(state.searchIndex == 0 && state.searchCount == 0 && state.searchResultQuery == nil,
               "Changing query invalidates old results")
        let otherState = AppState()
        _ = otherState.handleKey(key(3, "f", modifiers: .command))
        expect(!otherState.showingSearch, "No search without a document")
        print("PASS: keyboard layouts, toggle, navigation, Esc priority, query invalidation")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 760, height: 500),
                            configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = web
        window.makeKeyAndOrderFront(nil)

        func js(_ body: String, arguments: [String: Any] = [:]) -> Any {
            var result: Result<Any, Error>?
            web.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result = $0 }
            wait("JavaScript", until: { result != nil })
            switch result! {
            case .success(let value): return value
            case .failure(let error): fatalError("JavaScript error: \(error)")
            }
        }

        let fixture = """
        <p>Hello <strong>world</strong> HELLO world.</p>
        <p>Привет МИР — привет мир. Café café. 🐱 cat 🐱.</p>
        <p>Literal a+b [x] .* $ \\ and &lt;script&gt;.</p>
        <p>line\nbreak <em>inline</em><br>next</p>
        <p>separate</p><p>paragraphs</p>
        <p style="display:none">hiddenneedle</p>
        <pre><code>HELLO code</code></pre>
        """
        let paragraphs = (0..<70).map { "<p>Row \($0): needle</p>" }.joined()
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body {font:16px/1.7 system-ui; margin:0; padding:56px 44px 80px;}
        </style></head><body><article id="content">\(fixture)\(paragraphs)</article>
        <script>\(SearchScript.source)</script></body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
        wait("document load", until: { !web.isLoading && web.url != nil })
        let original = js("return document.getElementById('content').innerHTML;") as! String

        func search(_ query: String, count: Int, index: Int = 0, expectedIndex: Int = 0) {
            let result = js("return window.mdpSearch(query, index);",
                            arguments: ["query": query, "index": index]) as! [String: Any]
            expect(result["count"] as? Int == count, "Wrong count for '\(query)': \(result)")
            expect(result["index"] as? Int == expectedIndex, "Wrong index: \(result)")
        }
        search("hello", count: 3)
        search("hello world", count: 2)
        search("ПРИВЕТ мир", count: 2)
        search("CAFÉ", count: 2)
        search("🐱", count: 2)
        search("a+b", count: 1)
        search("[x]", count: 1)
        search(".*", count: 1)
        search("$", count: 1)
        search("\\", count: 1)
        search("<script>", count: 1)
        search("line break inline next", count: 1)
        search("separateparagraphs", count: 0)
        search("hiddenneedle", count: 0)
        search("absent", count: 0)
        search("   ", count: 0)
        search("needle", count: 70, index: -1, expectedIndex: 69)
        search("needle", count: 70, index: 70)

        let markerPixels = js("""
        const canvas = document.querySelectorAll('canvas')[1];
        const data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
        return Array.from(data).filter((value, i) => i % 4 === 3 && value > 0).length;
        """) as! Int
        expect(markerPixels > 200, "Expected scrollbar match markers")
        search("needle", count: 70, index: 69, expectedIndex: 69)
        expect((js("return window.scrollY;") as! Double) > 500, "Last match must be revealed")
        window.setContentSize(NSSize(width: 560, height: 400))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        search("hello world", count: 2)
        expect(js("return document.getElementById('content').innerHTML;") as? String == original,
               "Search must preserve Markdown DOM")
        search("", count: 0)
        expect(js("return Array.from(document.querySelectorAll('canvas')).every(c => c.hidden);") as? Bool == true,
               "Closing search must remove highlights and markers")

        // A horizontally clipped code match must be revealed, and its overlay
        // must follow the text when the user scrolls the code block manually.
        _ = js("""
        const pre = document.createElement('pre');
        pre.id = 'wide-code';
        pre.style.cssText = 'overflow:auto;width:300px;padding:16px;';
        pre.textContent = 'prefix ' + 'x'.repeat(300) + ' horizontalMatch ' + 'x'.repeat(100);
        document.getElementById('content').append(pre);
        """)
        search("horizontalMatch", count: 1)
        expect(js("return document.getElementById('wide-code').scrollLeft > 0;") as? Bool == true,
               "Search must reveal a match inside horizontally scrolling code")
        _ = js("""
        const pre = document.getElementById('wide-code');
        const range = document.createRange();
        const start = pre.firstChild.data.indexOf('horizontalMatch');
        range.setStart(pre.firstChild, start); range.setEnd(pre.firstChild, start + 15);
        window.testCodeRange = range;
        pre.scrollLeft -= 20;
        """)
        wait("highlight after code scrolling", until: {
            js("""
            const rect = window.testCodeRange.getBoundingClientRect();
            const canvas = document.querySelector('canvas'), scale = devicePixelRatio;
            const ctx = canvas.getContext('2d');
            const alpha = x => ctx.getImageData(Math.floor(x * scale), Math.floor((rect.top + 2) * scale), 1, 1).data[3];
            return alpha(rect.right - 2) > 0 && alpha(rect.left - 2) === 0;
            """) as? Bool == true
        })
        _ = js("document.getElementById('wide-code').scrollLeft = 0;")
        wait("offscreen code highlight cleared", until: {
            js("""
            const canvas = document.querySelector('canvas');
            const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
            return !Array.from(pixels).some((value, i) => i % 4 === 3 && value > 0);
            """) as? Bool == true
        })
        _ = js("document.getElementById('wide-code').remove();")

        // Exercise the asynchronous bridge, including a query changing while
        // an older JavaScript request is still pending.
        let coordinator = MarkdownWebView.Coordinator(state: state)
        coordinator.documentReady = true
        coordinator.loadedSignature = "fixture"
        state.showingSearch = true
        state.searchQuery = "needle"
        coordinator.updateSearch(in: web)
        state.searchQuery = "hello world"
        coordinator.updateSearch(in: web)
        wait("latest search result", until: { state.searchResultQuery == "hello world" })
        expect(state.searchCount == 2, "A stale result must not overwrite the new query")
        state.searchQuery = "needle"
        coordinator.updateSearch(in: web)
        wait("navigation results", until: { state.searchResultQuery == "needle" })
        state.moveSearch(-1)
        coordinator.updateSearch(in: web)
        wait("previous match", until: {
            (js("return window.scrollY;") as! Double) > 500
        })
        expect(state.searchIndex == 69, "Bridge must navigate to previous match")
        state.showingSearch = false
        coordinator.updateSearch(in: web)
        wait("close clears markers", until: {
            js("return Array.from(document.querySelectorAll('canvas')).every(c => c.hidden);") as? Bool == true
        })

        let navigationState = AppState(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        var externalURLs: [URL] = []
        let navigation = MarkdownWebView.Coordinator(state: navigationState,
                                                     openExternalURL: { externalURLs.append($0) })
        web.navigationDelegate = navigation
        let spacer = Array(repeating: "Paragraph for scrolling.\n\n", count: 40).joined()
        let hostileMarkdown = """
        # Safe title

        Literal closing tag: `</script>`.

        <p id="preserved">Ordinary HTML</p>
        <img id="bad-image" src="data:image/png;base64,broken" onerror="window.untrustedRan = true">
        <a id="script-link" href="javascript:window.untrustedRan=true">Script link</a>
        <a id="anchor-link" href="#section%20with%20space">Go to section</a>
        <a id="external-link" href="https://example.org/">External link</a>
        <form id="bad-form" action="about:blank#submitted"><input name="text" value="secret"></form>

        \(spacer)
        <h2 id="section with space">Target section</h2>

        \(spacer)
        """
        web.loadHTMLString(HTMLTemplate.render(markdown: hostileMarkdown),
                           baseURL: navigationState.currentURL!.deletingLastPathComponent())
        wait("protected Markdown", until: { navigation.documentReady })
        expect(js("return document.getElementById('preserved').textContent;") as? String == "Ordinary HTML",
               "Passive HTML must still render")
        expect(js("return document.getElementById('content').textContent.includes('</script>');") as? Bool == true,
               "A literal script closing tag must not break rendering")
        _ = js("""
        document.getElementById('bad-image').dispatchEvent(new Event('error'));
        document.getElementById('script-link').click();
        document.getElementById('bad-form').submit();
        """)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        expect(js("return window.untrustedRan !== true;") as? Bool == true,
               "Markdown event handlers and JavaScript links must not execute")
        expect(js("return !!document.getElementById('preserved');") as? Bool == true,
               "Markdown forms must not replace the preview")
        let documentURL = web.url
        _ = js("window.location.href = 'about:blank#redirected';")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        expect(web.url == documentURL, "Script navigation must not replace the preview")
        _ = js("document.getElementById('anchor-link').click();")
        wait("document fragment", until: {
            abs(js("return document.getElementById('section with space').getBoundingClientRect().top;") as! Double) < 2
        })
        expect(externalURLs.isEmpty, "A document anchor must not be sent to NSWorkspace")
        _ = js("document.getElementById('external-link').click();")
        wait("external link handling", until: { externalURLs.count == 1 })
        expect(externalURLs[0].absoluteString == "https://example.org/", "External links must use the system opener")
        expect(web.url == documentURL, "External links must keep the Markdown preview loaded")
        search("Safe title", count: 1)
        print("PASS: clipped code highlights, nested scrolling, CSP, passive HTML, anchors, external navigation")
        window.orderOut(nil)
        print("PASS: rendered text, inline formatting, Unicode, literals, block boundaries, wrap, markers, scroll, resize, cleanup")

        let searchState = AppState(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let searchWindow = MarkdownWindow(contentRect: NSRect(x: 100, y: 100, width: 760, height: 720),
                                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                         backing: .buffered, defer: false)
        searchWindow.state = searchState
        searchWindow.contentViewController = NSHostingController(
            rootView: ContentView(state: searchState).frame(minWidth: 560, minHeight: 420))
        searchWindow.configureDocumentToolbar()
        searchWindow.makeKeyAndOrderFront(nil)
        func findWebView(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.compactMap { findWebView($0) }.first
        }
        var documentWebView: WKWebView?
        wait("hosted document", until: {
            documentWebView = findWebView(searchWindow.contentView!)
            return documentWebView != nil && !documentWebView!.isLoading
        })
        searchWindow.makeFirstResponder(documentWebView)
        _ = searchState.handleKey(key(3, "а", modifiers: .command))
        wait("search input focus", until: { (searchWindow.firstResponder as? NSTextView)?.isFieldEditor == true })
        let editor = searchWindow.firstResponder as! NSTextView
        editor.insertText("hello", replacementRange: NSRange(location: NSNotFound, length: 0))
        wait("typing updates search", until: { searchState.searchQuery == "hello" })
        wait("typed query results", until: { searchState.searchResultQuery == "hello" })
        expect(searchState.searchCount == 2, "Typing in the focused input must search the document")
        _ = searchState.handleKey(key(3, "f", modifiers: .command))
        wait("return focus to document", until: { searchWindow.firstResponder === documentWebView })
        _ = searchState.handleKey(key(3, "а", modifiers: .command))
        wait("reopened search focus", until: { (searchWindow.firstResponder as? NSTextView)?.isFieldEditor == true })
        let reopenedEditor = searchWindow.firstResponder as! NSTextView
        expect(reopenedEditor.selectedRange().length == 5, "Reopening should select the existing query")
        searchWindow.orderOut(nil)
        print("PASS: asynchronous bridge, stale result handling, automatic search field focus")
    }
}
