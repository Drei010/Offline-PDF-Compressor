# Distribution

The release workflow creates a universal macOS 13+ app for Apple silicon and Intel, packages it as a ZIP, and writes a SHA-256 checksum and JSON manifest into `dist/`. It builds separately from the running development app and excludes PDF fixtures and UI tests.

## Current package

`dist/PDF-Compressor-1.0-universal-preview-unnotarized.zip` is an **unnotarized preview**. It is locally ad hoc signed with the hardened runtime; it has no Developer ID signature or Apple notarization ticket. It may be blocked by Gatekeeper on another Mac. A development certificate is installed on this machine, but no Developer ID Application certificate was available when packaging this preview.

Native UI click-through verification remains incomplete because macOS UI automation timed out. See the verification record in `README.md` before treating any package as a fully tested public release.

The preview ZIP passed all 11 Playwright integration/release checks, including extraction, SHA-256 consistency, both architecture slices, preserved signature and hardened runtime, and sandbox entitlement restrictions. Both binary slices declare macOS 13.0 as their minimum OS version. The Developer ID/notarization branch is prepared but has not been executed because the required signing identity is not installed.

## Create a notarized release

1. Install your **Developer ID Application** certificate and its private key in the macOS Keychain. Apple Development and Apple Distribution certificates are different types and are not accepted by this workflow. List usable identities with:

   ```sh
   security find-identity -v -p codesigning
   ```

2. Store notarization credentials locally using the interactive Keychain setup. Enter secrets only at its secure prompt; do not put passwords, private keys, or app-specific passwords in source files or chat:

   ```sh
   xcrun notarytool store-credentials "PDFCompressor-notary"
   ```

3. Run the release command with your certificate's exact identity name and the saved Keychain profile name:

   ```sh
   SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
   NOTARY_PROFILE='PDFCompressor-notary' \
   npm run release
   ```

The script builds both architectures, applies the hardened runtime and timestamped Developer ID signature, uploads the app ZIP to Apple's notary service, requires an `Accepted` status, staples and validates the ticket, checks Gatekeeper assessment, then creates the final ZIP **after stapling**. Only then does it write a manifest with `"notarized": true`.

The release step uploads the application binary to Apple. The application itself remains offline and never uploads PDFs. No release is published to a website or repository by this script.

The build log is `build/distribution-build.log`; the latest submission report is `build/notarization.json`. A failed or timed-out submission produces no new final package. If Apple is still processing a timed-out request, its submission ID remains in that report; inspect it with `xcrun notarytool info SUBMISSION_ID --keychain-profile PDFCompressor-notary`. Rerunning the release command creates a fresh submission.

## Rebuild a local preview

```sh
npm run release:preview
```

This explicitly bypasses the external signing/notarization step and labels both the filename and manifest accordingly. The default `npm run release` never silently falls back to a preview.

## Verify and install

```sh
cd dist
shasum -a 256 -c PDF-Compressor-1.0-universal.sha256
```

For a preview use the corresponding `-preview-unnotarized.sha256` filename. A matching checksum proves the archive matches the recorded bytes; it does not substitute for Developer ID signing or notarization.

For the notarized ZIP, extract it, move **PDF Compressor.app** into **Applications**, and open it. The document icon appears in the menu bar; there is no Dock icon. A fresh-Mac test should cover importing, compressing, saving, opening the result, and Finder reveal on both architectures. Both architectures are built and checked in the package; execution on Intel hardware has not been verified here.

Release verification commands:

```sh
swift test
npm test
npm run test:ui
```

The Playwright release checks validate signing guards and, when a generated package exists, its actual ZIP contents, architectures, signature, entitlement restrictions, and checksum. Native UI tests must run in a working macOS desktop automation session.

For later versions, update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist` before packaging. The ZIP, checksum, and manifest share the versioned basename; publish them together once signing, notarization, and verification are complete.

Apple references: [Notarization requirements](https://developer.apple.com/documentation/security/resolving-common-notarization-issues), [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).
