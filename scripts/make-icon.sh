#!/bin/bash
# Redraws Resources/AppIcon.icns from scripts/icon/main.swift. Only needed after changing the design.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -O -o "$out/icon" scripts/icon/main.swift
"$out/icon" --iconset "$out/AppIcon.iconset"
iconutil -c icns -o Resources/AppIcon.icns "$out/AppIcon.iconset"
echo "Wrote Resources/AppIcon.icns"
