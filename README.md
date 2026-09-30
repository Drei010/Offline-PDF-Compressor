# PDF Compressor

A native, offline macOS menu-bar utility. Requires macOS 13 or later; build with Xcode 16 or later (Swift 6). The app uses only Apple frameworks and has no backend, telemetry, network entitlement, or runtime package dependencies.

## Build and run

```sh
bash scripts/run.sh
```

This creates an ad hoc signed, sandboxed application at `build/PDF Compressor.app` and opens it. Click the document icon in the menu bar; the app intentionally has no Dock icon. Alternatively, open `PDFCompressor.xcodeproj` in Xcode and run the `PDFCompressor` scheme. Distribution to other Macs requires your own Developer ID signing and notarization.

For a universal ZIP and the signing/notarization workflow, see [RELEASE.md](RELEASE.md). `npm run release:preview` builds a labeled unnotarized preview; `npm run release` requires Developer ID and notarization credentials.

## Use

Drop one PDF into the popover or choose it with the file picker. Select Light, Balanced, Strong, or Custom, then compress. Custom accepts an approximate size in KB or MB (1 KB = 1,024 bytes); targets must be at least 1 KB and below the source size.

Save As writes a separate copy. Open PDF previews the result, and Show in Finder becomes available after saving. Settings persist the default preset, custom unit, filename pattern (`{name}` and `{preset}`), initial save-folder behavior, and reveal-after-save preference.

Password-protected and invalid PDFs are rejected. A document that cannot be reduced keeps its original bytes and shows “Already optimized.” A custom target that cannot be reached returns the smallest valid result with a clear message.

## Compression and file safety

- PDFKit writes through a native Quartz image filter: Light uses 0.90 JPEG quality / 300 DPI; Balanced uses 0.75 / 180 DPI; Strong uses 0.55 / 120 DPI. Pages are not rasterized.
- Custom tries up to seven progressively stronger configurations from the original snapshot, stopping when a valid result meets the target. It never recompresses an earlier lossy result.
- Each candidate must reopen and preserve page count, extracted text, page boxes, rotation, and supported annotations/link destinations. Larger or invalid candidates are discarded. Automated rendering comparisons cover the generated fixture corpus; arbitrary PDF features and visual fidelity cannot be proven by structural checks alone.
- The app takes a security-scoped snapshot on import and performs analysis/compression away from the main actor. Progress reports native PDFKit page-write notifications and compression passes. **Cancel takes effect when the current native PDFKit write returns**, then deletes intermediate files and returns to the ready state.
- Saving stages a copy beside the destination before atomic replacement. The original’s device/inode identity is retained on import, protecting it even after renaming, as well as its symlink and hard-link aliases. Working files are removed when starting another document, cancelling work, or quitting normally.

## Tests

```sh
swift test                    # Swift Testing: generated PDFs, fidelity, targets, saving, cancellation
npm ci
npx playwright --version
npm test                      # Playwright CLI: integration checks against the real Swift engine
npm run test:ui               # XCTest/XCUIAutomation: real native controls and screenshots
```

Playwright cannot drive AppKit/SwiftUI controls. It runs the command-line compression checks, while XCTest verifies native interactions and captures screenshots in `test-screenshots/*.xcresult`. UI tests require a logged-in macOS desktop with UI automation permitted. They use a dedicated settings suite and a window containing the same menu-bar view; a separate test opens the normal menu-bar popover.

The deterministic fixture generator covers text, images, scans, vectors, mixed content, links and notes, already-optimized files, unusual page sizes/rotation, a 120-page file, encrypted PDFs, and corrupt input. Generate files for manual testing with:

```sh
PDF_TEST_FIXTURES_PATH="$PWD/Tests/Fixtures" swift test --filter exportFixtureCorpus
```

For a restricted build environment, point `CLANG_MODULE_CACHE_PATH` and `SWIFT_MODULECACHE_PATH` at writable temporary directories and pass `--disable-sandbox` to SwiftPM if nested sandboxing is unavailable. These flags are unnecessary in a normal terminal.

## Layout

`Sources/PDFCompressor` contains the SwiftUI interface and application state. `Sources/PDFCompressorCore` contains analysis, configuration, compression, and safe saving. `Sources/PDFCompressorCLI` exposes the same engine for automated integration tests. Swift tests are in `Tests/PDFCompressorCoreTests`, Playwright checks in `Tests/Integration`, and native UI tests in `UITests`.

The V2 items from the plan—batch processing, Finder actions, history, protected PDFs, automatic recommendations, visual comparison UI, lossless-only and flattened modes—remain outside this release. Optional launch-at-login is not included.

## Verification recorded on 2026-09-30

All 13 Swift tests passed, including nine document variants and app-state transitions; all 11 Playwright checks passed, covering real PDFs plus the universal release ZIP and signing safeguards. The Xcode application and seven native UI tests compiled and signed successfully. Balanced reduced the generated image/scanned fixture from 6,288,210 to 1,098,337 bytes (82.53%); one local CLI run took 0.158 seconds with 55.3 MB peak resident memory. These measurements describe the generated fixture, not arbitrary documents.

Native UI execution remains unverified: an elevated XCTest run failed before any test method with `Timed out while enabling automation mode`. The result bundle is `test-screenshots/Native-20260930-002403.xcresult`. Computer-use inspection also timed out for the exact Debug app path, although the app was running and a process sample showed its main thread idle in the normal AppKit event loop. No native screenshots or successful UI interactions are claimed. In particular, menu-bar interactions, file dialogs, Save As, and Finder reveal still need a working desktop automation session.

Successful native runs export window screenshots into `test-screenshots/native/`. A single test can be run with `npm run test:ui -- -only-testing:PDFCompressorUITests/PDFCompressorUITests/testIdleAndSettings`.
