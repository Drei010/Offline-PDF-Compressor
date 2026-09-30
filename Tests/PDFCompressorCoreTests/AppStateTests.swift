import Foundation
import Testing
@testable import PDFCompressor

@Suite(.serialized) @MainActor
struct AppStateTests {
    @Test func importCompressAndResetUsesOneSnapshotAndCleansUp() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try PDFFixture.image.write(in: folder)
        let second = try PDFFixture.text.write(in: folder)
        let original = try Data(contentsOf: source)
        let state = AppState()
        defer { state.terminate() }
        state.importPDF(source)
        state.importPDF(second) // A second import must not replace an active job.
        #expect(state.phase == .analyzing)
        try await waitUntilFinished(state)
        #expect(state.phase == .ready)
        let snapshot = try #require(state.info?.sourceURL)
        #expect(snapshot != source)
        #expect(state.info?.fileName == source.lastPathComponent)
        state.preset = "balanced"
        state.compress()
        state.compress() // Only one output may be produced.
        #expect(state.phase == .compressing)
        try await waitUntilFinished(state)
        #expect(state.phase == .completed)
        let result = try #require(state.result)
        #expect(result.compressedBytes < result.originalBytes)
        #expect(try Data(contentsOf: source) == original)
        state.reset()
        #expect(state.phase == .idle)
        #expect(state.result == nil)
        #expect(!FileManager.default.fileExists(atPath: snapshot.deletingLastPathComponent().path))
    }

    @Test func cancellationReturnsToReadyAndAllowsRetry() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try PDFFixture.image.write(in: folder)
        let state = AppState()
        defer { state.terminate() }
        state.importPDF(source)
        try await waitUntilFinished(state)
        state.preset = "strong"
        state.compress()
        state.cancel()
        try await waitUntilFinished(state)
        #expect(state.phase == .ready)
        #expect(state.result == nil)
        #expect(state.errorMessage == nil)
        state.compress()
        try await waitUntilFinished(state)
        #expect(state.phase == .completed)
        state.reset()
    }

    @Test func invalidImportAndCustomInputRemainRecoverable() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let corrupt = try PDFFixture.corrupt.write(in: folder)
        let text = try PDFFixture.text.write(in: folder)
        let state = AppState()
        defer { state.terminate() }
        state.importPDF(corrupt)
        try await waitUntilFinished(state)
        #expect(state.phase == .failed)
        #expect(state.errorMessage?.isEmpty == false)
        state.importPDF(text)
        try await waitUntilFinished(state)
        #expect(state.phase == .ready)
        state.preset = "custom"
        state.targetUnit = "KB"
        state.targetText = "0"
        #expect(state.selectedPreset == nil)
        state.compress()
        #expect(state.phase == .ready)
        state.targetText = "1"
        #expect(state.selectedPreset == .custom(targetBytes: 1_024))
        state.reset()
    }

    private func waitUntilFinished(_ state: AppState) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while state.busy && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!state.busy, "The app did not finish its background job within 20 seconds")
    }
}
