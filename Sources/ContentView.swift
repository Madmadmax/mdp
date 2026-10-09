import SwiftUI

let backgroundColor = Color(red: 0.11, green: 0.11, blue: 0.12)

struct ContentView: View {
    @StateObject private var state: AppState

    init(state: AppState = AppState()) {
        _state = StateObject(wrappedValue: state)
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            if let url = state.currentURL {
                MarkdownWebView(url: url, reloadToken: state.reloadToken, state: state)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                EmptyPrompt()
            }

            if state.showingList {
                FileListView()
                    .environmentObject(state)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if state.showingSearch {
                SearchBar(state: state)
                    .padding(.top, 8)
                    .padding(.trailing, 18)
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.showingList)
    }
}

struct EmptyPrompt: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Open a markdown file")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }
}
