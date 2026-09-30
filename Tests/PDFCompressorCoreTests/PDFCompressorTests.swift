import Foundation
import PDFKit
import Testing
@testable import PDFCompressorCore

@Test func exportFixtureCorpus() throws {
    guard let path = ProcessInfo.processInfo.environment["PDF_TEST_FIXTURES_PATH"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for fixture in PDFFixture.allCases { _ = try fixture.write(in: directory) }
}

@Suite(.serialized)
struct PDFCompressorTests {
    @Test func presetConfigurationAndTargetValidation() throws {
        #expect(CompressionPreset.light.configuration.jpegQuality == 0.90)
        #expect(CompressionPreset.balanced.configuration.jpegQuality == 0.75)
        #expect(CompressionPreset.strong.configuration.jpegQuality == 0.55)
        #expect(CompressionPreset.light.configuration.maxDPI == 300)
        #expect(CompressionPreset.balanced.configuration.maxDPI == 180)
        #expect(CompressionPreset.strong.configuration.maxDPI == 120)
        for preset in [CompressionPreset.light, .balanced, .strong, .custom(targetBytes: 8192)] {
            #expect(preset.configuration.preserveText)
            #expect(preset.configuration.optimizeImages)
        }
        #expect(CompressionPreset.custom(targetBytes: 8192).configuration.targetBytes == 8192)
        #expect(try TargetSize.bytes(from: "1.5", unit: .mb, originalBytes: 3_000_000) == 1_572_864)
        #expect(try TargetSize.bytes(from: "16", unit: .kb, originalBytes: 3_000_000) == 16_384)
        for invalid in ["", "zero", "0", "-2", "NaN", "inf", "1e100", String(repeating: "9", count: 1000)] {
            #expect(throws: CompressionError.invalidTargetSize) {
                try TargetSize.bytes(from: invalid, unit: .mb, originalBytes: 3_000_000)
            }
        }
        #expect(throws: CompressionError.invalidTargetSize) {
            try TargetSize.bytes(from: "3", unit: .mb, originalBytes: 3_000_000)
        }
    }

    @Test func analyzerRejectsInvalidAndEncryptedDocuments() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = try PDFFixture.text.write(in: directory)
        let info = try PDFAnalyzer.analyze(text)
        #expect(info.sourceURL == text)
        #expect(info.fileName == "text-only.pdf")
        #expect(info.pageCount == 2)
        #expect(info.originalBytes == Int64(try Data(contentsOf: text).count))
        let corrupt = try PDFFixture.corrupt.write(in: directory)
        #expect(throws: (any Error).self) { try PDFAnalyzer.analyze(corrupt) }
        let encrypted = try PDFFixture.encrypted.write(in: directory)
        #expect(throws: CompressionError.encryptedPDF) { try PDFAnalyzer.analyze(encrypted) }
        #expect(throws: (any Error).self) { try PDFAnalyzer.analyze(directory.appendingPathComponent("missing.pdf")) }
    }

    @Test(arguments: [PDFFixture.text, .image, .scanned, .vector, .mixed, .annotations, .optimized, .unusual, .large])
    func preservesUsableDocument(_ fixture: PDFFixture) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture.write(in: directory)
        let original = try Data(contentsOf: source)
        let destination = directory.appendingPathComponent("compressed.pdf")
        let result = try await PDFCompressor().compress(source: source, destination: destination, preset: .balanced)
        let before = try #require(PDFDocument(url: source))
        let after = try #require(PDFDocument(url: result.outputURL))
        #expect(after.pageCount == before.pageCount)
        #expect(result.pageCount == before.pageCount)
        #expect(result.originalBytes == original.count)
        #expect(result.compressedBytes == Int64(try Data(contentsOf: result.outputURL).count))
        #expect(result.compressedBytes > 0)
        #expect(result.compressedBytes <= result.originalBytes)
        #expect(result.bytesSaved == result.originalBytes - result.compressedBytes)
        #expect(result.percentSaved >= 0 && result.percentSaved <= 100)
        #expect(try Data(contentsOf: source) == original)
        for pageIndex in 0..<after.pageCount {
            let originalPage = try #require(before.page(at: pageIndex))
            let outputPage = try #require(after.page(at: pageIndex))
            #expect(outputPage.bounds(for: .mediaBox) == originalPage.bounds(for: .mediaBox))
            #expect(outputPage.bounds(for: .cropBox) == originalPage.bounds(for: .cropBox))
            #expect(outputPage.rotation == originalPage.rotation)
            if fixture.containsText { #expect(outputPage.string == originalPage.string) }
            #expect(outputPage.annotations.count == originalPage.annotations.count)
            for (old, new) in zip(originalPage.annotations, outputPage.annotations) {
                #expect(old.type == new.type)
                #expect(old.url == new.url)
                #expect(old.contents == new.contents)
            }
        }
        let rendered = try #require(after.page(at: 0)?.thumbnail(of: CGSize(width: 160, height: 160), for: .mediaBox))
        #expect(rendered.size.width > 0 && rendered.size.height > 0)
        #expect(rendered.tiffRepresentation?.isEmpty == false)
        let beforePixels = try pixels(of: #require(before.page(at: 0)))
        let afterPixels = try pixels(of: #require(after.page(at: 0)))
        let difference = zip(beforePixels, afterPixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        #expect(Double(difference) / Double(255 * beforePixels.count) < 0.05)
        if [.image, .scanned, .mixed].contains(fixture) {
            #expect(result.compressedBytes < result.originalBytes / 2)
            print("\(fixture.rawValue): \(result.originalBytes) → \(result.compressedBytes) bytes (\(result.percentSaved)% saved)")
        }
        if fixture == .optimized {
            #expect(result.isAlreadyOptimized)
            #expect(try Data(contentsOf: result.outputURL) == original)
        }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(Set(remaining).isSubset(of: Set([source.lastPathComponent, destination.lastPathComponent])))
    }

    @Test func imagePresetsAndCustomTarget() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try PDFFixture.image.write(in: directory)
        var sizes: [Int64] = []
        for (index, preset) in [CompressionPreset.light, .balanced, .strong].enumerated() {
            let result = try await PDFCompressor().compress(source: source, destination: directory.appendingPathComponent("preset-\(index).pdf"), preset: preset)
            #expect(result.compressedBytes < result.originalBytes)
            sizes.append(result.compressedBytes)
        }
        #expect(sizes[2] < sizes[0])
        let target = sizes[1]
        let result = try await PDFCompressor().compress(source: source, destination: directory.appendingPathComponent("target.pdf"), preset: .custom(targetBytes: target))
        #expect(result.targetBytes == target)
        #expect(result.targetReached)
        #expect(result.compressedBytes <= target)
    }

    @Test func unreachableTargetReturnsBestValidOutput() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try PDFFixture.text.write(in: directory)
        let progress = ProgressLog()
        let result = try await PDFCompressor().compress(source: source, destination: directory.appendingPathComponent("unreachable.pdf"), preset: .custom(targetBytes: 1024)) { progress.record($0) }
        #expect(!result.targetReached)
        #expect(result.targetBytes == 1024)
        #expect(result.compressedBytes <= result.originalBytes)
        #expect(PDFDocument(url: result.outputURL)?.pageCount == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count <= 2)
        let updates = progress.updates
        #expect(updates.filter { $0.message.hasPrefix("Compressing") }.count <= 7)
        #expect(updates.contains { $0.message.hasPrefix("Processing page") })
        #expect(updates.last?.fraction == 1)
        #expect(updates.allSatisfy { (0...1).contains($0.fraction) })
        #expect(zip(updates, updates.dropFirst()).allSatisfy { $0.fraction <= $1.fraction })
    }

    @Test func invalidTargetAndOriginalOverwriteAreRejected() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try PDFFixture.text.write(in: directory)
        let original = try Data(contentsOf: source)
        for target in [Int64(0), 1023, Int64(original.count), Int64.max] {
            await #expect(throws: CompressionError.invalidTargetSize) {
                try await PDFCompressor().compress(source: source, destination: directory.appendingPathComponent("invalid.pdf"), preset: .custom(targetBytes: target))
            }
        }
        await #expect(throws: (any Error).self) {
            try await PDFCompressor().compress(source: source, destination: source, preset: .strong)
        }
        let alias = directory.appendingPathComponent("alias.pdf")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        await #expect(throws: (any Error).self) {
            try await PDFCompressor().compress(source: source, destination: alias, preset: .strong)
        }
        for destination in [directory.appendingPathComponent("invalid.txt"), URL(string: "https://example.com/output.pdf")!] {
            await #expect(throws: CompressionError.cannotWriteOutput) {
                try await PDFCompressor().compress(source: source, destination: destination, preset: .balanced)
            }
        }
        #expect(try Data(contentsOf: source) == original)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("invalid.pdf").path))
    }

    @Test func savingIsAtomicAndProtectsOriginalAliases() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try PDFFixture.text.write(in: directory)
        let original = try Data(contentsOf: source)
        let result = try await PDFCompressor().compress(source: source, destination: directory.appendingPathComponent("working.pdf"), preset: .balanced)
        let saved = directory.appendingPathComponent("saved.pdf")
        try FileService.save(result: result, to: saved, originalURL: source)
        #expect(PDFDocument(url: saved)?.pageCount == 2)
        try Data("existing unrelated content".utf8).write(to: saved)
        try FileService.save(result: result, to: saved, originalURL: source)
        #expect(try Data(contentsOf: saved) == Data(contentsOf: result.outputURL))
        let alias = directory.appendingPathComponent("hardlink.pdf")
        try FileManager.default.linkItem(at: source, to: alias)
        let symlink = directory.appendingPathComponent("symlink.pdf")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        for forbidden in [source, alias, symlink, result.outputURL] {
            #expect(throws: CompressionError.cannotOverwriteOriginal) {
                try FileService.save(result: result, to: forbidden, originalURL: source)
            }
        }
        #expect(try Data(contentsOf: source) == original)
        let previousSave = try Data(contentsOf: saved)
        try FileManager.default.removeItem(at: result.outputURL)
        #expect(throws: CompressionError.cannotWriteOutput) {
            try FileService.save(result: result, to: saved, originalURL: source)
        }
        #expect(try Data(contentsOf: saved) == previousSave)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 4)
    }

    @Test func savingProtectsOriginalMovedAfterImport() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try PDFFixture.image.write(in: directory)
        let original = try Data(contentsOf: source)
        let identity = try FileService.identity(of: source)
        let snapshot = directory.appendingPathComponent("snapshot.pdf")
        try FileManager.default.copyItem(at: source, to: snapshot)
        let result = try await PDFCompressor().compress(source: snapshot, destination: directory.appendingPathComponent("result.pdf"), preset: .balanced)
        let moved = directory.appendingPathComponent("renamed-original.pdf")
        try FileManager.default.moveItem(at: source, to: moved)
        let alias = directory.appendingPathComponent("renamed-alias.pdf")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: moved)
        for destination in [moved, alias] {
            #expect(throws: CompressionError.cannotOverwriteOriginal) {
                try FileService.save(result: result, to: destination, originalURL: source, originalIdentity: identity)
            }
        }
        #expect(try Data(contentsOf: moved) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 4)
    }

    @Test func cancellationCleansUpAndPreservesSource() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try PDFFixture.large.write(in: directory)
        let original = try Data(contentsOf: source)
        let destination = directory.appendingPathComponent("cancelled.pdf")
        let cancellation = CancellationHandle()
        let task = Task {
            try await PDFCompressor().compress(source: source, destination: destination, preset: .custom(targetBytes: 1024)) { progress in
                if progress.message.hasPrefix("Processing page") { cancellation.cancel() }
            }
        }
        cancellation.attach(task)
        await #expect(throws: CompressionError.cancelled) { try await task.value }
        #expect(try Data(contentsOf: source) == original)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [source.lastPathComponent])
    }
}

private func pixels(of page: PDFPage) throws -> [UInt8] {
    let dimension = 128
    var pixels = [UInt8](repeating: 255, count: dimension * dimension * 4)
    try pixels.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(data: buffer.baseAddress, width: dimension, height: dimension,
                                            bitsPerComponent: 8, bytesPerRow: dimension * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let box = page.bounds(for: .mediaBox)
        let scale = min(CGFloat(dimension) / box.width, CGFloat(dimension) / box.height)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: context)
    }
    return pixels
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [CompressionProgress] = []

    var updates: [CompressionProgress] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ progress: CompressionProgress) {
        lock.lock()
        recorded.append(progress)
        lock.unlock()
    }
}

private final class CancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<CompressionResult, Error>?
    private var requested = false

    func attach(_ task: Task<CompressionResult, Error>) {
        lock.lock()
        self.task = task
        let shouldCancel = requested
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        requested = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}
