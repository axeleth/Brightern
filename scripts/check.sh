#!/bin/bash
# Checks the brightness mapping, and with --live, that the running app keeps the monitor in sync.
# --live briefly sets the MacBook to 30% and 70%, reads the monitor back over DDC, then restores it.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -O -o "$out/check" scripts/check/main.swift \
    Sources/Brightern/{PrivateAPI,TernMonitor,BuiltInDisplay,BrightnessCurve}.swift
"$out/check" "$@"
