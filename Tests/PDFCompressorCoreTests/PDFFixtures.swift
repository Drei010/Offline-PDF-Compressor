import AppKit
import CoreText
import PDFKit

enum PDFFixture: String, CaseIterable, Sendable {
    case text = "text-only"
    case image = "image-heavy"
    case scanned
    case vector = "vector-heavy"
    case mixed
    case annotations
    case optimized = "already-compressed"
    case unusual = "unusual-pages"
    case large
    case encrypted
    case corrupt

    var containsText: Bool { [.text, .mixed, .annotations, .unusual, .large].contains(self) }

    func write(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(rawValue).appendingPathExtension("pdf")
        if self == .corrupt {
            try Data("%PDF-1.7\nThis document is deliberately corrupt.\n".utf8).write(to: url)
            return url
        }
        if self == .optimized {
            try Self.minimalPDF.write(to: url)
            return url
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let pageCount = self == .large ? 120 : 2
        let image = [.image, .scanned, .mixed].contains(self) ? Self.image() : nil
        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            if let image {
                context.draw(image, in: CGRect(x: 24, y: 100, width: 564, height: 650))
            }
            if containsText || self == .encrypted {
                Self.text("Selectable PDF fixture — page \(page + 1)", at: CGPoint(x: 42, y: 60), in: context)
                Self.text("Offline compression keeps these words searchable.", at: CGPoint(x: 42, y: 40), in: context)
            }
            if self == .vector || self == .mixed {
                for line in 0..<80 {
                    context.setStrokeColor(CGColor(red: CGFloat(line % 5) / 5, green: 0.3, blue: 0.7, alpha: 1))
                    context.setLineWidth(0.7)
                    context.move(to: CGPoint(x: 30, y: 110 + line * 7))
                    context.addCurve(to: CGPoint(x: 580, y: 110 + line * 7), control1: CGPoint(x: 180, y: 750), control2: CGPoint(x: 450, y: 50))
                    context.strokePath()
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
        if self == .annotations || self == .unusual || self == .encrypted {
            guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if self == .annotations {
                let link = PDFAnnotation(bounds: CGRect(x: 42, y: 55, width: 300, height: 20), forType: .link, withProperties: nil)
                link.url = URL(string: "https://example.com/offline-fixture")
                page.addAnnotation(link)
                let note = PDFAnnotation(bounds: CGRect(x: 400, y: 100, width: 28, height: 28), forType: .text, withProperties: nil)
                note.contents = "Keep this annotation."
                page.addAnnotation(note)
            }
            if self == .unusual {
                page.setBounds(CGRect(x: -20, y: -30, width: 640, height: 850), for: .mediaBox)
                page.setBounds(CGRect(x: 10, y: 20, width: 580, height: 750), for: .cropBox)
                page.rotation = 90
                document.page(at: 1)?.setBounds(CGRect(x: 0, y: 0, width: 1000, height: 500), for: .mediaBox)
            }
            let options: [PDFDocumentWriteOption: Any] = self == .encrypted
                ? [.userPasswordOption: "fixture-password", .ownerPasswordOption: "fixture-owner"] : [:]
            guard document.write(to: url, withOptions: options) else { throw CocoaError(.fileWriteUnknown) }
        }
        return url
    }

    private static func text(_ string: String, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textPosition = point
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        CTLineDraw(line, context)
    }

    private static func image() -> CGImage {
        let width = 1500, height = 1800
        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        var seed: UInt32 = 73
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Int(seed >> 27)
                let index = (y * width + x) * 3
                pixels[index] = UInt8((x * 180 / width + noise) % 256)
                pixels[index + 1] = UInt8((y * 180 / height + noise) % 256)
                pixels[index + 2] = UInt8((x / 10 + y / 10 + noise) % 256)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                       bytesPerRow: width * 3, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    private static var minimalPDF: Data {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
            "<< /Length 4 >>\nstream\nq Q\nendstream"
        ]
        var pdf = "%PDF-1.3\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 5\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}

func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFCompressorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
