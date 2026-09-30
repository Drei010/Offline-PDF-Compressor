#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration" --product PDFCompressor
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/build/PDF Compressor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/PDFCompressor" "$app/Contents/MacOS/PDFCompressor"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --entitlements Resources/PDFCompressor.entitlements "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"
