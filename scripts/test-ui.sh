#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PDF_TEST_FIXTURES_PATH="$PWD/Tests/Fixtures" swift test --filter exportFixtureCorpus
swift scripts/make-ui-fixture.swift "$PWD/Tests/Fixtures"
mkdir -p test-screenshots
result="$PWD/test-screenshots/Native-$(date +%Y%m%d-%H%M%S).xcresult"
test_status=0
xcodebuild test -project PDFCompressor.xcodeproj -scheme PDFCompressor \
  -destination 'platform=macOS' -derivedDataPath "$PWD/build/Xcode" \
  -resultBundlePath "$result" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES "$@" || test_status=$?
xcrun xcresulttool export attachments --path "$result" --output-path "$PWD/test-screenshots/native" || true
exit "$test_status"
