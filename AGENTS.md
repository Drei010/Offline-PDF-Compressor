# Agent Directives

## Code Generation and Modification

When generating, writing, or modifying any code in this project:
1. Use the Ponytail skill for all code-related tasks
2. Apply the Ponytail skill's guidelines for code structure, style, and best practices
3. Reference the Ponytail skill documentation for language-specific conventions

## Testing and Quality Assurance

- Configure and use Playwright as the testing framework
- All new features must include Playwright test coverage
- Use Playwright CLI for automated testing and screenshot capture
- Screenshots should document:
  - UI state before and after functionality
  - Edge cases and error states
  - Cross-browser rendering (if applicable)

## Continuous Compliance

- Re-read this file at the beginning of each work session
- Ensure all outputs align with the directives above

## 6. Native macOS Verification

- This is a native SwiftUI app. Use Swift Testing for PDF fixtures and XCTest/XCUIAutomation for native controls and screenshots.
- Playwright runs command-line integration checks against the real Swift compression engine; browser screenshots are not evidence of native UI behavior.
- Keep the app offline. Never upload PDFs or overwrite the imported original.
