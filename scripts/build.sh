#!/bin/bash
# Builds build/Brightern.app with the Command Line Tools' Swift (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)"

app=build/Brightern.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/Brightern" "$app/Contents/MacOS/Brightern"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $app"
