import Foundation

public enum CompressionPreset: Equatable, Sendable {
    case light, balanced, strong
    case custom(targetBytes: Int64)

    public var configuration: CompressionConfiguration {
        switch self {
        case .light: return .init(jpegQuality: 0.90, maxDPI: 300)
        case .balanced: return .init(jpegQuality: 0.75, maxDPI: 180)
        case .strong: return .init(jpegQuality: 0.55, maxDPI: 120)
        case .custom(let bytes): return .init(jpegQuality: 0.90, maxDPI: nil, targetBytes: bytes)
        }
    }
}

public struct CompressionConfiguration: Equatable, Sendable {
    public let jpegQuality: Double
    public let maxDPI: Double?
    public let optimizeImages = true
    public let preserveText = true
    public let targetBytes: Int64?

    public init(jpegQuality: Double, maxDPI: Double?, targetBytes: Int64? = nil) {
        self.jpegQuality = jpegQuality
        self.maxDPI = maxDPI
        self.targetBytes = targetBytes
    }
}

public enum SizeUnit: String, CaseIterable, Sendable {
    case kb = "KB", mb = "MB"

    public var multiplier: Int64 { self == .kb ? 1_024 : 1_048_576 }
}

public enum TargetSize {
    public static let minimumBytes: Int64 = 1_024

    public static func bytes(from text: String, unit: SizeUnit, originalBytes: Int64) throws -> Int64 {
        guard text.utf8.count <= 128 else { throw CompressionError.invalidTargetSize }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw CompressionError.invalidTargetSize
        }
        let bytes = value * Decimal(unit.multiplier)
        guard bytes >= Decimal(minimumBytes), bytes < Decimal(originalBytes), bytes <= Decimal(Int64.max) else {
            throw CompressionError.invalidTargetSize
        }
        return NSDecimalNumber(decimal: bytes).int64Value
    }
}

public struct PDFInfo: Sendable {
    public let sourceURL: URL
    public let fileName: String
    public let originalBytes: Int64
    public let pageCount: Int
    public let pageSizes: [CGSize]
    public let containsText: Bool
    public let hasAnnotations: Bool

    public init(sourceURL: URL, fileName: String, originalBytes: Int64, pageCount: Int,
                pageSizes: [CGSize] = [], containsText: Bool = false, hasAnnotations: Bool = false) {
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.originalBytes = originalBytes
        self.pageCount = pageCount
        self.pageSizes = pageSizes
        self.containsText = containsText
        self.hasAnnotations = hasAnnotations
    }
}

public struct CompressionProgress: Sendable {
    public let fraction: Double
    public let message: String

    public init(fraction: Double, message: String) {
        self.fraction = fraction
        self.message = message
    }
}

public struct CompressionResult: Sendable {
    public let sourceURL: URL
    public let outputURL: URL
    public let originalBytes: Int64
    public let compressedBytes: Int64
    public let pageCount: Int
    public let targetBytes: Int64?
    public var isAlreadyOptimized: Bool { compressedBytes >= originalBytes }
    public var targetReached: Bool { targetBytes.map { compressedBytes <= $0 } ?? true }
    public var bytesSaved: Int64 { max(0, originalBytes - compressedBytes) }
    public var percentSaved: Double { originalBytes > 0 ? 100 * Double(bytesSaved) / Double(originalBytes) : 0 }

    public init(sourceURL: URL, outputURL: URL, originalBytes: Int64, compressedBytes: Int64,
                pageCount: Int, targetBytes: Int64? = nil) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.originalBytes = originalBytes
        self.compressedBytes = compressedBytes
        self.pageCount = pageCount
        self.targetBytes = targetBytes
    }
}

public enum CompressionError: LocalizedError, Equatable {
    case invalidPDF, encryptedPDF, unreadablePDF, invalidTargetSize
    case insufficientDiskSpace, cannotWriteOutput, cannotOverwriteOriginal
    case compressionFailed, cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidPDF: return "Choose a valid PDF containing at least one readable page."
        case .encryptedPDF: return "Password-protected PDFs are not supported. Choose an unencrypted copy."
        case .unreadablePDF: return "This PDF could not be read. Check its file permissions and try again."
        case .invalidTargetSize: return "Enter a target of at least 1 KB and smaller than the original PDF."
        case .insufficientDiskSpace: return "There is not enough free space to write the compressed PDF."
        case .cannotWriteOutput: return "The PDF could not be saved to this location. Choose another filename or folder."
        case .cannotOverwriteOriginal: return "Choose a different filename. The imported original is always preserved."
        case .compressionFailed: return "A valid compressed PDF could not be produced. Your original is unchanged."
        case .cancelled: return "Compression cancelled."
        }
    }
}
