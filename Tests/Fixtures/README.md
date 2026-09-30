# Generated PDF fixtures

The Swift test suite creates deterministic, real PDFs using Core Graphics and PDFKit; no customer documents or downloads are needed. Generate a reusable corpus for command-line and native UI checks:

```sh
PDF_TEST_FIXTURES_PATH="$PWD/Tests/Fixtures" swift test --filter exportFixtureCorpus
```

The corpus contains selectable text, textured images, image-only scans, vectors, mixed content, links and notes, a minimal already-optimized PDF, rotated and unusual page boxes, a 120-page document, a password-protected PDF, and a corrupt PDF. The encrypted fixture password is `fixture-password`; V1 rejects protected documents.

Generated PDFs are ignored by Git. Fixture source is `Tests/PDFCompressorCoreTests/PDFFixtures.swift`.
