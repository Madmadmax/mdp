#!/bin/bash
# Build mdp.app — compiles the Swift sources and assembles a runnable .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP="mdp.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "→ compiling…"
mkdir -p "$MACOS" "$RES"
swiftc Sources/*.swift \
    -o "$MACOS/mdp" \
    -parse-as-library \
    -target arm64-apple-macos14.0 \
    -framework SwiftUI -framework WebKit -framework AppKit \
    -O

echo "→ assembling bundle…"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/marked.min.js "$RES/marked.min.js"

echo "→ ad-hoc codesign…"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ built $APP"
