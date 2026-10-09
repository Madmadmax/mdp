#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mdp-search-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
cp Resources/marked.min.js "$TEST_DIR/marked.min.js"
printf '# Hello\n\nHello world\n' > "$TEST_DIR/fixture.md"
# Build the app classes without the SwiftUI application entry point.
sed '/^@main/,$d' Sources/App.swift > "$TEST_DIR/App.swift"
swiftc "$TEST_DIR/App.swift" Tests/SearchTests.swift \
    Sources/ContentView.swift Sources/FileListView.swift Sources/HTMLTemplate.swift \
    Sources/MarkdownWebView.swift Sources/SearchBar.swift Sources/SearchScript.swift \
    -parse-as-library -target arm64-apple-macos14.0 \
    -module-cache-path "$TEST_DIR/cache" \
    -framework SwiftUI -framework WebKit -framework AppKit \
    -o "$TEST_DIR/search-tests"
"$TEST_DIR/search-tests" "$TEST_DIR/fixture.md"
