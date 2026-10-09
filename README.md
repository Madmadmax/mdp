# mdp

A lightweight Markdown viewer for macOS with a clean, dark reading experience.
Open a file, find what you need, and browse other Markdown files in the same folder.
Each document opens in its own window.

Requires an Apple silicon Mac running macOS 14 or later.

## Getting started

1. Drag `mdp.app` to your **Applications** folder.
2. In Finder, right-click a Markdown file and choose **Open With → mdp**.

If you are starting from the source code, follow the [build instructions](#building-from-source) below to create `mdp.app`.

To use mdp as your default Markdown viewer, select a `.md` file in Finder,
choose **Get Info**, select **mdp** under **Open with**, then click **Change All…**.

## Reading documents

mdp displays headings, lists, tables, links, images, checkboxes, and code blocks.
Long lines of code scroll horizontally.

The window header shows the filename and its file icon. Drag the icon into a
messenger to attach the original Markdown file, or into Finder to copy it.

Markdown rendering and search run locally. Documents can load remote images;
external links open in the appropriate default app. JavaScript embedded in a
Markdown document is blocked.

## Finding text

Press **Cmd+F** to open the search bar in the upper-right corner and start typing.
The shortcut works regardless of your keyboard layout.

Matches are highlighted as you type, without case sensitivity. The counter shows
your current match and the total number of results. Marks along the scrollbar
show where matches appear in the document; the active match is orange.

- **Enter** or the down button moves to the next match.
- **Shift+Enter** or the up button moves to the previous match.
- Navigation wraps around when you reach the first or last match.
- **Cmd+F**, **Esc**, or the close button closes search.

## Browsing nearby files

Press **Esc** while reading to see the Markdown files in the current document's
folder. Choose a file with **↑ / ↓**, then press **Enter** to open it in the same
window. You can also click a filename. Press **Esc** again to close the list.

If search is open, the first **Esc** closes search; the next opens the file list.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| **Cmd+F** | Open or close search |
| **Enter** in search | Next match |
| **Shift+Enter** in search | Previous match |
| **Esc** | Close search or the file list; otherwise open the file list |
| **↑ / ↓** in the file list | Select a file |
| **Enter** in the file list | Open the selected file |

## Building from source

Requires macOS and the Xcode toolchain with Swift 6.

```bash
./build.sh
```

This creates an ad-hoc–signed `mdp.app` for Apple silicon in the project folder.
Move it to **Applications**, or launch it directly:

```bash
open -a ./mdp.app /path/to/document.md
```

To run the integration tests:

```bash
./test.sh
```

Tests use local AppKit windows and WebKit and require a logged-in macOS desktop session.

## Project layout

The app uses SwiftUI and AppKit for its interface, WebKit for document display,
and a bundled [marked](https://marked.js.org) parser for Markdown.

| File | Purpose |
|---|---|
| `Sources/App.swift` | Windows, document state, and keyboard shortcuts |
| `Sources/ContentView.swift` | Document view and overlays |
| `Sources/FileListView.swift` | Nearby-file browser |
| `Sources/MarkdownWebView.swift` | WebKit display, search bridge, and link handling |
| `Sources/HTMLTemplate.swift` | Markdown rendering, styling, and content security policy |
| `Sources/SearchBar.swift` | Search input and navigation controls |
| `Sources/SearchScript.swift` | Text matching, highlights, and scrollbar markers |
| `Resources/marked.min.js` | Bundled Markdown parser |
| `Tests/SearchTests.swift` | Integration tests |
| `Info.plist` | App metadata and supported document types |
| `build.sh` / `test.sh` | Build and test scripts |
