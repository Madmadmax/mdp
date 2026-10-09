import SwiftUI
import AppKit

/// Focus after SwiftUI has attached the field to the window, rather than during
/// onAppear when WKWebView can still own the window's first responder.
private final class SearchTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            if window.makeFirstResponder(self) { self.selectText(nil) }
        }
    }
}

private struct SearchInput: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextField {
        let field = SearchTextField()
        field.isBordered = false
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.placeholderString = "Find in document"
        field.setAccessibilityLabel("Find in document")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

struct SearchBar: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            SearchInput(text: $state.searchQuery)
                .frame(width: 150)
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
                .accessibilityLabel("Search results: \(status)")
            button("chevron.up", help: "Previous match (Shift+Enter)") { state.moveSearch(-1) }
                .disabled(state.searchCount == 0)
            button("chevron.down", help: "Next match (Enter)") { state.moveSearch(1) }
                .disabled(state.searchCount == 0)
            Divider().frame(height: 16)
            button("xmark", help: "Close search (Esc or Cmd+F)") { state.showingSearch = false }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }

    private var status: String {
        if state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        if state.searchResultQuery != state.searchQuery { return "…" }
        if state.searchCount == 0 { return "No matches" }
        return "\(state.searchIndex + 1) of \(state.searchCount)"
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 16, height: 18)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
