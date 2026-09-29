#!/bin/bash
# Builds Brightern and installs it to /Applications, then opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh

osascript -e 'tell application id "com.axelehrnrooth.brightern" to quit' 2>/dev/null || true
rm -rf ~/Applications/Brightern.app  # where versions before 1.1 were installed
rm -rf /Applications/Brightern.app
cp -R build/Brightern.app /Applications/Brightern.app
open /Applications/Brightern.app

echo "Installed /Applications/Brightern.app"
