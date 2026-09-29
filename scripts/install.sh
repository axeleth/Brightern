#!/bin/bash
# Builds Brightern and installs it to ~/Applications (no admin rights needed), then opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh

osascript -e 'tell application id "com.axelehrnrooth.brightern" to quit' 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/Brightern.app
cp -R build/Brightern.app ~/Applications/Brightern.app
open ~/Applications/Brightern.app

echo "Installed ~/Applications/Brightern.app — look for the sun icon in the menu bar."
