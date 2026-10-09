import SwiftUI

/// Escape overlay: the markdown files living next to the current file.
/// Navigation is arrows + enter (handled centrally in AppState.handleKey);
/// rows are also clickable.
struct FileListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.06))
                list
            }
            .frame(maxWidth: 520, maxHeight: 460)
            .background(Color(red: 0.13, green: 0.13, blue: 0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(40)
        }
    }

    private var header: some View {
        HStack {
            Text(folderName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("↑↓ navigate · ↵ open · esc close")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(state.markdownFiles.enumerated()), id: \.element) { index, url in
                        FileRow(
                            name: url.lastPathComponent,
                            isSelected: index == state.selectedIndex,
                            isCurrent: url == state.currentURL
                        )
                        .id(index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            state.selectedIndex = index
                            state.openSelection()
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: state.selectedIndex) { _, idx in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(idx, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(state.selectedIndex, anchor: .center) }
        }
    }

    private var folderName: String {
        state.currentURL?.deletingLastPathComponent().lastPathComponent ?? ""
    }
}

private struct FileRow: View {
    let name: String
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isCurrent ? "doc.text.fill" : "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : Color(white: 0.82))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
        )
    }
}
