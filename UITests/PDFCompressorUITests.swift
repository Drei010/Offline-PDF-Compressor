import PDFKit
import XCTest

final class PDFCompressorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
    }

    @MainActor private func launch(fixture: String? = nil) {
        app.launchArguments = ["--uitesting"]
        if let fixture { app.launchArguments += ["--fixture", fixture] }
        app.launch()
    }

    @MainActor private func capture(_ name: String) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testIdleAndSettings() {
        launch()
        XCTAssertTrue(app.buttons["choosePDF"].waitForExistence(timeout: 10))
        capture("01-idle")
        app.buttons["settingsButton"].click()
        XCTAssertTrue(app.textFields["filenamePattern"].waitForExistence(timeout: 5))
        capture("02-settings")
        app.buttons["settingsDone"].click()
        XCTAssertTrue(app.buttons["choosePDF"].exists)
    }

    @MainActor func testImportCustomValidationCompressionAndReset() {
        launch(fixture: "image-heavy")
        let compress = app.buttons["compressPDF"]
        XCTAssertTrue(compress.waitForExistence(timeout: 15))
        XCTAssertTrue(compress.isEnabled)
        capture("03-ready")
        app.segmentedControls["presetPicker"].buttons["Custom"].click()
        let target = app.textFields["customTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.click()
        target.typeKey("a", modifierFlags: .command)
        target.typeText("0")
        XCTAssertFalse(compress.isEnabled)
        capture("04-invalid-target")
        app.segmentedControls["presetPicker"].buttons["Strong"].click()
        XCTAssertTrue(compress.isEnabled)
        compress.click()
        XCTAssertTrue(app.buttons["savePDF"].waitForExistence(timeout: 90))
        XCTAssertTrue(app.buttons["openPDF"].isEnabled)
        XCTAssertFalse(app.buttons["revealPDF"].isEnabled)
        capture("05-completed")
        app.buttons["savePDF"].click()
        let savePanel = app.dialogs.firstMatch
        XCTAssertTrue(savePanel.waitForExistence(timeout: 10))
        capture("06-save-panel")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFCompressor-UITest-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: destination) }
        let filename = savePanel.textFields.firstMatch
        filename.click()
        filename.typeKey("a", modifierFlags: .command)
        filename.typeText(destination.lastPathComponent)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(destination.deletingLastPathComponent().path)
        app.typeKey(.return, modifierFlags: [])
        savePanel.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["savedMessage"].waitForExistence(timeout: 10))
        XCTAssertEqual(PDFDocument(url: destination)?.pageCount, 2)
        XCTAssertTrue(app.buttons["revealPDF"].isEnabled)
        capture("06-saved")
        app.buttons["revealPDF"].click()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 10))
        app.activate()
        app.buttons["compressAnother"].click()
        XCTAssertTrue(app.buttons["choosePDF"].waitForExistence(timeout: 5))
    }

    @MainActor func testCorruptPDFShowsActionableError() {
        launch(fixture: "corrupt")
        XCTAssertTrue(app.staticTexts["errorMessage"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["choosePDF"].exists)
        XCTAssertFalse(app.buttons["compressPDF"].exists)
        capture("07-corrupt-pdf")
    }

    @MainActor func testEncryptedPDFShowsActionableError() {
        launch(fixture: "encrypted")
        XCTAssertTrue(app.staticTexts["errorMessage"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["choosePDF"].exists)
        capture("08-encrypted-pdf")
    }

    @MainActor func testAlreadyOptimizedDocument() {
        launch(fixture: "already-compressed")
        XCTAssertTrue(app.buttons["compressPDF"].waitForExistence(timeout: 10))
        app.buttons["compressPDF"].click()
        XCTAssertTrue(app.buttons["savePDF"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Already optimized"].exists)
        capture("09-already-optimized")
    }

    @MainActor func testCancelReturnsToReady() {
        launch(fixture: "cancellation")
        XCTAssertTrue(app.buttons["compressPDF"].waitForExistence(timeout: 15))
        app.buttons["compressPDF"].click()
        XCTAssertTrue(app.buttons["cancelCompression"].waitForExistence(timeout: 5))
        capture("10-compressing")
        app.buttons["cancelCompression"].click()
        XCTAssertTrue(app.buttons["compressPDF"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.buttons["compressPDF"].isEnabled)
        XCTAssertFalse(app.buttons["savePDF"].exists)
        capture("11-cancelled")
    }

    @MainActor func testMenuBarPopover() {
        app.launchArguments = []
        app.launch()
        let icon = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        icon.click()
        XCTAssertTrue(app.buttons["choosePDF"].waitForExistence(timeout: 10))
        capture("12-menu-bar-popover")
    }
}
