import Foundation
import PDFKit

// A genuine multi-page image workload keeps cancellation observable to XCUIAutomation.
let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let input = PDFDocument(url: fixtures.appendingPathComponent("image-heavy.pdf"))!
let output = PDFDocument()
for index in 0..<120 {
    output.insert(input.page(at: index % input.pageCount)!.copy() as! PDFPage, at: index)
}
guard output.write(to: fixtures.appendingPathComponent("cancellation.pdf")) else { exit(1) }
