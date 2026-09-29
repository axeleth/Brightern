#!/bin/bash
# Removes everything Brightern added: the login item, the app, and its settings.
set -uo pipefail

app=~/Applications/Brightern.app

osascript -e 'tell application id "com.axelehrnrooth.brightern" to quit' 2>/dev/null
if [ -x "$app/Contents/MacOS/Brightern" ]; then
    "$app/Contents/MacOS/Brightern" --unregister-login-item
fi
rm -rf "$app"
defaults delete com.axelehrnrooth.brightern 2>/dev/null

echo "Brightern removed. The monitor keeps its last brightness; its own buttons work as before."
