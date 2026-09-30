// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PDFCompressor",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PDFCompressorCore", targets: ["PDFCompressorCore"]),
        .executable(name: "PDFCompressor", targets: ["PDFCompressor"]),
        .executable(name: "pdf-compressor", targets: ["PDFCompressorCLI"])
    ],
    targets: [
        .target(name: "PDFCompressorCore"),
        .executableTarget(name: "PDFCompressor", dependencies: ["PDFCompressorCore"]),
        .executableTarget(name: "PDFCompressorCLI", dependencies: ["PDFCompressorCore"]),
        .testTarget(name: "PDFCompressorCoreTests", dependencies: ["PDFCompressorCore", "PDFCompressor"])
    ],
    swiftLanguageModes: [.v5]
)
