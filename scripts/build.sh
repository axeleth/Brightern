#!/bin/bash
# Builds build/Brightern.app with the Command Line Tools' Swift (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)"

app=build/Brightern.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Brightern" "$app/Contents/MacOS/Brightern"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"

echo "Built $app"
