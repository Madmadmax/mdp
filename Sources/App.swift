import SwiftUI
import AppKit
import Combine

final class AppState: ObservableObject {
    @Published var currentURL: URL?
    @Published var showingList = false
    @Published var markdownFiles: [URL] = []
    @Published var selectedIndex = 0
    /// Bumped whenever the file content should be re-read (open / reload).
    @Published var reloadToken = 0
    @Published var showingSearch = false
    @Published var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            searchIndex = 0
            searchCount = 0
            searchResultQuery = nil
        }
    }
    @Published var searchIndex = 0
    @Published var searchCount = 0
    @Published var searchResultQuery: String?

    private static let markdownExtensions: Set<String> =
        ["md", "markdown", "mdown", "mkd", "mkdn", "mdtext", "text"]

    init(url: URL? = nil) {
        if let url {
            open(url)
        }
    }

    func open(_ url: URL) {
        currentURL = url
        showingList = false
        showingSearch = false
        searchQuery = ""
        reloadToken += 1
        refreshFiles()
        if let idx = markdownFiles.firstIndex(of: url) { selectedIndex = idx }
    }

    func refreshFiles() {
        guard let dir = currentURL?.deletingLastPathComponent() else {
            markdownFiles = []
            return
        }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        markdownFiles = items
            .filter { Self.markdownExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func showList() {
        guard currentURL != nil else { return }
        showingSearch = false
        refreshFiles()
        if let cur = currentURL, let idx = markdownFiles.firstIndex(of: cur) {
            selectedIndex = idx
        } else {
            selectedIndex = min(selectedIndex, max(markdownFiles.count - 1, 0))
        }
        showingList = true
    }

    private func moveSelection(_ delta: Int) {
        guard !markdownFiles.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + markdownFiles.count) % markdownFiles.count
    }

    func openSelection() {
        guard markdownFiles.indices.contains(selectedIndex) else { return }
        open(markdownFiles[selectedIndex])
    }

    func toggleSearch() {
        guard currentURL != nil else { return }
        showingSearch.toggle()
        if showingSearch { showingList = false }
    }

    func moveSearch(_ delta: Int) {
        guard showingSearch, searchCount > 0 else { return }
        searchIndex = (searchIndex + delta + searchCount) % searchCount
    }

    /// Central key handling. Returns nil to swallow the event.
    func handleKey(_ event: NSEvent) -> NSEvent? {
        let escape: UInt16 = 53, down: UInt16 = 125, up: UInt16 = 126
        let ret: UInt16 = 36, enter: UInt16 = 76
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // Use the physical F key, including when it produces Cyrillic "а".
        if event.keyCode == 3 && modifiers == .command {
            toggleSearch()
            return nil
        }

        if event.keyCode == escape {
            if showingSearch { showingSearch = false }
            else if showingList { showingList = false }
            else { showList() }
            return nil
        }
        if showingSearch, (event.keyCode == ret || event.keyCode == enter),
           modifiers.subtracting(.shift).isEmpty {
            moveSearch(modifiers.contains(.shift) ? -1 : 1)
            return nil
        }
        if showingList {
            switch event.keyCode {
            case down:        moveSelection(1);  return nil
            case up:          moveSelection(-1); return nil
            case ret, enter:  openSelection();   return nil
            default:          break
            }
        }
        return event
    }
}

/// A file icon that exports the file itself through AppKit's dragging system.
final class DocumentIconView: NSImageView, NSDraggingSource {
    var fileURL: URL?

    override func mouseDown(with event: NSEvent) {
        // Keep the mouse sequence here rather than letting NSImageView track it.
    }

    override func mouseDragged(with event: NSEvent) {
        guard let fileURL, let image else { return }
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

final class DocumentTitleView: NSStackView {
    let icon = DocumentIconView()
    let label = NSTextField(labelWithString: "mdp")

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 6
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(icon)
        addArrangedSubview(label)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(url: URL?) {
        icon.fileURL = url
        icon.image = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        icon.isHidden = url == nil
        label.stringValue = url?.lastPathComponent ?? "mdp"
        toolTip = url?.path
        icon.setAccessibilityLabel(url.map { "Drag \($0.lastPathComponent)" })
    }
}

final class MarkdownWindow: NSWindow, NSToolbarDelegate {
    private var documentObservation: AnyCancellable?
    private let documentTitleView = DocumentTitleView()
    private static let documentTitleIdentifier = NSToolbarItem.Identifier("DocumentTitle")

    var state: AppState? {
        didSet {
            documentObservation = nil
            representedURL = state?.currentURL
            title = state?.currentURL?.lastPathComponent ?? "mdp"
            documentTitleView.update(url: state?.currentURL)
            documentObservation = state?.$currentURL.sink { [weak self] url in
                self?.representedURL = url
                self?.title = url?.lastPathComponent ?? "mdp"
                self?.documentTitleView.update(url: url)
            }
        }
    }

    func configureDocumentToolbar() {
        titleVisibility = .hidden
        toolbarStyle = .unifiedCompact
        let toolbar = NSToolbar(identifier: "DocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Self.documentTitleIdentifier]
        self.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.documentTitleIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.documentTitleIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == Self.documentTitleIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Current file"
        item.view = documentTitleView
        item.isBordered = false
        return item
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let frameAutosaveName = "MainWindow"

    private var windows: [NSWindow] = []
    private var statesByWindow: [ObjectIdentifier: AppState] = [:]
    private var pendingOpenURLs: [URL] = []
    private var didFinishLaunching = false
    private var keyEventMonitor: Any?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard didFinishLaunching else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        openDocuments(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        NSApp.appearance = NSAppearance(named: .darkAqua)
        installKeyEventMonitor()

        let initialURLs = pendingOpenURLs.isEmpty ? Self.commandLineURLs() : pendingOpenURLs
        pendingOpenURLs.removeAll()
        if initialURLs.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.windows.isEmpty else { return }
                self.openWindow(url: nil)
            }
        } else {
            openDocuments(initialURLs)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow(url: nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.saveFrame(usingName: Self.frameAutosaveName)
        windows.removeAll { $0 === window }
        statesByWindow.removeValue(forKey: ObjectIdentifier(window))
    }

    private func openDocuments(_ urls: [URL]) {
        closeUntitledWindows()
        for url in urls {
            openWindow(url: url)
        }
    }

    private func openWindow(url: URL?) {
        let state = AppState(url: url)
        let window = MarkdownWindow(
            contentRect: Self.defaultFrame(),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.state = state

        window.contentViewController = NSHostingController(
            rootView: ContentView(state: state)
                .frame(minWidth: 560, minHeight: 420))
        window.isReleasedWhenClosed = false
        window.delegate = self

        Self.apply(to: window)
        window.configureDocumentToolbar()
        Self.restoreFrame(of: window)
        windows.append(window)
        statesByWindow[ObjectIdentifier(window)] = state
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Intercept navigation before SwiftUI or WKWebView can turn arrow-key
    /// events into scrolling.
    private func installKeyEventMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = (event.window ?? NSApp.keyWindow) as? MarkdownWindow,
                  let state = window.state else {
                return event
            }
            return state.handleKey(event)
        }
    }

    private func closeUntitledWindows() {
        let untitledWindows = windows.filter {
            statesByWindow[ObjectIdentifier($0)]?.currentURL == nil
        }
        for window in untitledWindows {
            window.close()
        }
    }

    private static func commandLineURLs() -> [URL] {
        CommandLine.arguments.dropFirst().compactMap { arg in
            guard !arg.hasPrefix("-") else { return nil }
            let url = URL(fileURLWithPath: (arg as NSString).expandingTildeInPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private static func defaultFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 760, height: 720)
        }
        let visible = screen.visibleFrame
        let width = visible.width * 0.5
        let height = visible.height * 0.95
        let origin = NSPoint(
            x: visible.minX + (visible.width - width) / 2,
            y: visible.minY + (visible.height - height) / 2)
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    private static func restoreFrame(of window: NSWindow) {
        if !window.setFrameUsingName(frameAutosaveName) {
            migrateLegacySwiftUIFrame(to: window)
        }
        window.setFrameAutosaveName(frameAutosaveName)
    }

    /// Older SwiftUI-managed windows used a generated autosave key. Preserve
    /// that frame once when moving to the stable AppKit window name.
    private static func migrateLegacySwiftUIFrame(to window: NSWindow) {
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        guard let savedFrame = defaults.first(where: { key, value in
            key.hasPrefix("NSWindow Frame ") &&
                key.contains("-AppWindow-") &&
                value is String
        })?.value as? String else {
            return
        }
        window.setFrame(from: savedFrame)
        window.saveFrame(usingName: frameAutosaveName)
    }

    /// Minimalist chrome with content extending under the transparent titlebar.
    private static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

@main
struct MDPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
