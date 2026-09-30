import Foundation
import PDFKit
import Quartz

public enum PDFAnalyzer {
    public static func analyze(_ url: URL) throws -> PDFInfo {
        let document = try open(url)
        var sizes: [CGSize] = []
        var containsText = false
        var hasAnnotations = false
        for index in 0..<document.pageCount {
            try checkCancellation()
            guard let page = document.page(at: index), page.pageRef != nil else { throw CompressionError.invalidPDF }
            let box = page.bounds(for: .mediaBox)
            guard box.origin.x.isFinite, box.origin.y.isFinite,
                  box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else {
                throw CompressionError.invalidPDF
            }
            sizes.append(box.size)
            containsText = containsText || page.numberOfCharacters > 0
            hasAnnotations = hasAnnotations || !page.annotations.isEmpty
        }
        return PDFInfo(sourceURL: url, fileName: url.lastPathComponent,
                       originalBytes: try fileSize(url), pageCount: document.pageCount,
                       pageSizes: sizes, containsText: containsText, hasAnnotations: hasAnnotations)
    }

    fileprivate static func open(_ url: URL) throws -> PDFDocument {
        guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { throw CompressionError.invalidPDF }
        guard FileManager.default.isReadableFile(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw CompressionError.unreadablePDF
        }
        guard let document = PDFDocument(url: url) else { throw CompressionError.invalidPDF }
        guard !document.isEncrypted, !document.isLocked else { throw CompressionError.encryptedPDF }
        guard document.pageCount > 0 else { throw CompressionError.invalidPDF }
        return document
    }
}

public struct PDFCompressor: Sendable {
    public init() {}

    public func compress(source: URL, destination: URL, preset: CompressionPreset,
                         progress: @escaping @Sendable (CompressionProgress) -> Void = { _ in }) async throws -> CompressionResult {
        try checkCancellation()
        let info = try PDFAnalyzer.analyze(source)
        let target = preset.configuration.targetBytes
        if let target, target < TargetSize.minimumBytes || target >= info.originalBytes {
            throw CompressionError.invalidTargetSize
        }
        guard destination.isFileURL, destination.pathExtension.lowercased() == "pdf" else { throw CompressionError.cannotWriteOutput }
        guard !FileService.sameFile(source, destination) else { throw CompressionError.cannotOverwriteOriginal }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CompressionError.cannotWriteOutput }

        let folder = destination.deletingLastPathComponent().appendingPathComponent(".pdf-compressor-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        catch { throw FileService.writeError(error) }
        defer { try? FileManager.default.removeItem(at: folder) }

        // ponytail: seven descending image settings bound work; add a finer quality search only if measured results need it.
        let attempts: [CompressionConfiguration] = target == nil ? [preset.configuration] : [
            .init(jpegQuality: 0.90, maxDPI: nil), .init(jpegQuality: 0.80, maxDPI: 300),
            .init(jpegQuality: 0.70, maxDPI: 220), .init(jpegQuality: 0.60, maxDPI: 180),
            .init(jpegQuality: 0.50, maxDPI: 144), .init(jpegQuality: 0.40, maxDPI: 96),
            .init(jpegQuality: 0.30, maxDPI: 72)
        ]
        var bestURL = source
        var bestBytes = info.originalBytes
        for (index, configuration) in attempts.enumerated() {
            try checkCancellation()
            progress(.init(fraction: Double(index) / Double(attempts.count),
                           message: "Compressing · pass \(index + 1) of \(attempts.count)"))
            try checkCancellation()
            let candidate = folder.appendingPathComponent("pass-\(index).pdf")
            let accepted = try autoreleasepool {
                let document = try PDFAnalyzer.open(source)
                guard let filter = Self.filter(configuration) else { throw CompressionError.compressionFailed }
                // PDFKit's documented QuartzFilter option rewrites images without rasterizing text, vectors, or annotations.
                let options: [PDFDocumentWriteOption: Any] = [
                    PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter,
                    .burnInAnnotationsOption: false
                ]
                let observer = NotificationCenter.default.addObserver(forName: .PDFDocumentDidEndPageWrite, object: document, queue: nil) { notification in
                    guard let page = notification.userInfo?[PDFDocumentPageIndexKey] as? Int else { return }
                    let completed = min(info.pageCount, page + 1)
                    let fraction = (Double(index) + 0.9 * Double(completed) / Double(info.pageCount)) / Double(attempts.count)
                    progress(.init(fraction: fraction, message: "Processing page \(completed) of \(info.pageCount) · pass \(index + 1)"))
                }
                defer { NotificationCenter.default.removeObserver(observer) }
                guard document.write(to: candidate, withOptions: options) else { throw CompressionError.cannotWriteOutput }
                try checkCancellation() // PDFKit writes cannot be interrupted; discard the pass immediately afterward.
                return try Self.preservesDocument(candidate, original: document)
            }
            if accepted {
                let bytes = try fileSize(candidate)
                if bytes > 0, bytes < bestBytes {
                    if bestURL != source { try? FileManager.default.removeItem(at: bestURL) }
                    bestURL = candidate
                    bestBytes = bytes
                } else { try? FileManager.default.removeItem(at: candidate) }
            } else { try? FileManager.default.removeItem(at: candidate) }
            progress(.init(fraction: Double(index + 1) / Double(attempts.count), message: "Checked \(info.pageCount) pages · pass \(index + 1) complete"))
            if let target, bestBytes <= target { break }
        }

        try checkCancellation()
        do {
            if bestURL == source {
                bestURL = folder.appendingPathComponent("original.pdf")
                try FileManager.default.copyItem(at: source, to: bestURL)
            }
            try checkCancellation()
            try FileManager.default.moveItem(at: bestURL, to: destination)
        } catch let error as CompressionError { throw error }
        catch { throw FileService.writeError(error) }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: destination)
            throw CompressionError.cancelled
        }
        progress(.init(fraction: 1, message: bestBytes < info.originalBytes ? "Compression complete" : "Already optimized"))
        return CompressionResult(sourceURL: source, outputURL: destination, originalBytes: info.originalBytes,
                                 compressedBytes: bestBytes, pageCount: info.pageCount, targetBytes: target)
    }

    private static func filter(_ configuration: CompressionConfiguration) -> QuartzFilter? {
        var images: [String: Any] = ["Compression Quality": configuration.jpegQuality, "ImageCompression": "ImageJPEGCompress"]
        if let dpi = configuration.maxDPI {
            images["ImageScaleSettings"] = ["ImageResolution": dpi, "ImageScaleInterpolate": true,
                                           "ImageSizeMax": 100_000, "ImageSizeMin": 0]
        }
        // These keys follow macOS's built-in /System/Library/Filters/Reduce File Size.qfilter schema.
        return QuartzFilter(properties: ["Domains": ["Applications": true], "FilterType": 1,
                                         "Name": "PDF Compressor", "FilterData": ["ColorSettings": ["ImageSettings": images]]])
    }

    private static func preservesDocument(_ url: URL, original: PDFDocument) throws -> Bool {
        guard let output = PDFDocument(url: url), output.pageCount == original.pageCount, !output.isLocked else { return false }
        for index in 0..<original.pageCount {
            try checkCancellation()
            guard let before = original.page(at: index), let after = output.page(at: index), after.pageRef != nil,
                  before.rotation == after.rotation, before.string == after.string,
                  before.annotations.count == after.annotations.count else { return false }
            for box: PDFDisplayBox in [.mediaBox, .cropBox, .bleedBox, .trimBox, .artBox] {
                if !equalBounds(before.bounds(for: box), after.bounds(for: box)) { return false }
            }
            for (a, b) in zip(before.annotations, after.annotations) {
                guard a.type == b.type, equalBounds(a.bounds, b.bounds), a.contents == b.contents,
                      a.url == b.url, a.fieldName == b.fieldName, a.widgetStringValue == b.widgetStringValue else { return false }
                if let action = a.action as? PDFActionURL, action.url != (b.action as? PDFActionURL)?.url { return false }
                if let action = a.action as? PDFActionGoTo {
                    guard let next = b.action as? PDFActionGoTo,
                          action.destination.point == next.destination.point,
                          let oldPage = action.destination.page, let newPage = next.destination.page,
                          original.index(for: oldPage) == output.index(for: newPage) else { return false }
                }
            }
        }
        return true
    }

    private static func equalBounds(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.01 && abs(lhs.minY - rhs.minY) < 0.01 &&
        abs(lhs.width - rhs.width) < 0.01 && abs(lhs.height - rhs.height) < 0.01
    }
}

private func checkCancellation() throws {
    if Task.isCancelled { throw CompressionError.cancelled }
}

private func fileSize(_ url: URL) throws -> Int64 {
    guard let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
        throw CompressionError.unreadablePDF
    }
    return bytes.int64Value
}
