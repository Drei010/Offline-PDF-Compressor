import Foundation
import PDFCompressorCore

@main
struct PDFCompressorCommand {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else { throw CLIError.usage }
            switch command {
            case "analyze":
                guard arguments.count == 2 else { throw CLIError.usage }
                let info = try PDFAnalyzer.analyze(URL(fileURLWithPath: arguments[1]))
                try emit([
                    "fileName": info.fileName, "originalBytes": info.originalBytes,
                    "pageCount": info.pageCount
                ])
            case "compress":
                guard (4...5).contains(arguments.count) else { throw CLIError.usage }
                let preset: CompressionPreset
                switch arguments[3] {
                case "light": preset = .light
                case "balanced": preset = .balanced
                case "strong": preset = .strong
                case "custom":
                    guard arguments.count == 5, let bytes = Int64(arguments[4]) else {
                        throw CLIError.usage
                    }
                    preset = .custom(targetBytes: bytes)
                default: throw CLIError.usage
                }
                guard arguments[3] == "custom" || arguments.count == 4 else { throw CLIError.usage }
                let result = try await PDFCompressor().compress(
                    source: URL(fileURLWithPath: arguments[1]),
                    destination: URL(fileURLWithPath: arguments[2]), preset: preset
                )
                try emit([
                    "outputPath": result.outputURL.path,
                    "originalBytes": result.originalBytes,
                    "compressedBytes": result.compressedBytes,
                    "pageCount": result.pageCount,
                    "bytesSaved": result.bytesSaved,
                    "percentSaved": result.percentSaved,
                    "isAlreadyOptimized": result.isAlreadyOptimized,
                    "targetReached": result.targetReached,
                    "targetBytes": result.targetBytes as Any? ?? NSNull()
                ])
            default: throw CLIError.usage
            }
        } catch {
            let data = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription]))
                ?? Data("{\"error\":\"Compression failed.\"}".utf8)
            FileHandle.standardOutput.write(data + Data([10]))
            exit(1)
        }
    }

    private static func emit(_ value: [String: Any]) throws {
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) + Data([10]))
    }
}

private enum CLIError: LocalizedError {
    case usage
    var errorDescription: String? {
        "Usage: pdf-compressor analyze INPUT | compress INPUT OUTPUT light|balanced|strong|custom [TARGET_BYTES]"
    }
}
