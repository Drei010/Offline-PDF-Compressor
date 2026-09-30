#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

preview=false
if [[ $# -eq 1 && "$1" == "--unsigned" ]]; then
  preview=true
elif [[ $# -ne 0 ]]; then
  printf '%s\n' 'Usage: bash scripts/release.sh [--unsigned]' >&2
  exit 2
fi

if [[ "$preview" == false ]]; then
  if [[ "${SIGNING_IDENTITY:-}" != 'Developer ID Application: '* || -z "${NOTARY_PROFILE:-}" ]]; then
    printf '%s\n' 'Set SIGNING_IDENTITY to a Developer ID Application identity and NOTARY_PROFILE to a notarytool Keychain profile. Use --unsigned only for an unnotarized preview.' >&2
    exit 2
  fi
  if ! security find-identity -v -p codesigning | grep -F -- "\"$SIGNING_IDENTITY\"" >/dev/null; then
    printf '%s\n' 'The requested Developer ID Application signing identity is not available in the Keychain.' >&2
    exit 2
  fi
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
[[ "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ && "$build_number" =~ ^[0-9]+$ ]] || { printf '%s\n' 'Use numeric release version and build values in Resources/Info.plist.' >&2; exit 2; }

mkdir -p build dist
stage=$(mktemp -d "$PWD/build/release.XXXXXX")
trap 'rm -rf "$stage"' EXIT

# Build both architectures in a separate directory; never replace the running development app.
if ! xcodebuild -quiet -project PDFCompressor.xcodeproj -scheme PDFCompressor \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$PWD/build/Distribution" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build > "$PWD/build/distribution-build.log" 2>&1; then
  tail -60 "$PWD/build/distribution-build.log" >&2
  exit 1
fi

app="$stage/PDF Compressor.app"
ditto "$PWD/build/Distribution/Build/Products/Release/PDFCompressor.app" "$app"
[[ ! -e "$app/Contents/Resources/Fixtures" ]] || { printf '%s\n' 'Release must not include test fixtures.' >&2; exit 1; }
for arch in arm64 x86_64; do
  lipo "$app/Contents/MacOS/PDFCompressor" -verify_arch "$arch"
done

stem="PDF-Compressor-$version-universal"
notarized=false
if [[ "$preview" == true ]]; then
  stem="$stem-preview-unnotarized"
  codesign --force --sign - --options runtime --timestamp=none \
    --entitlements Resources/PDFCompressor.entitlements "$app"
else
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    --entitlements Resources/PDFCompressor.entitlements "$app"
fi
codesign --verify --strict "$app"

if [[ "$preview" == false ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/submission.zip"
  if ! xcrun notarytool submit "$stage/submission.zip" --keychain-profile "$NOTARY_PROFILE" \
    --wait --timeout 20m --output-format json > "$PWD/build/notarization.json"; then
    printf '%s\n' 'Notarization did not complete successfully. See build/notarization.json; no new release was published.' >&2
    exit 1
  fi
  [[ "$(plutil -extract status raw -o - "$PWD/build/notarization.json")" == Accepted ]] || {
    printf '%s\n' 'Apple did not accept this submission. See build/notarization.json; no new release was published.' >&2
    exit 1
  }
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  codesign --verify --strict "$app"
  spctl --assess --type execute --verbose=2 "$app"
  notarized=true
fi

# Recreate the ZIP after stapling so the ticket travels with the app for offline verification.
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$stem.zip"
checksum=$(shasum -a 256 "$stage/$stem.zip" | awk '{print $1}')
cat > "$stage/$stem.json" <<EOF
{
  "version": "$version",
  "build": "$build_number",
  "architectures": ["arm64", "x86_64"],
  "archive": "$stem.zip",
  "sha256": "$checksum",
  "notarized": $notarized
}
EOF
printf '%s  %s\n' "$checksum" "$stem.zip" > "$stage/$stem.sha256"
mv "$stage/$stem.zip" "$stage/$stem.json" "$stage/$stem.sha256" "$PWD/dist/"
printf 'Package: %s/dist/%s.zip\nNotarized: %s\n' "$PWD" "$stem" "$notarized"
if [[ "$preview" == true ]]; then
  printf '%s\n' 'Preview only: locally ad hoc signed, without Developer ID or notarization. Gatekeeper may block it on other Macs.'
fi
