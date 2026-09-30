import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var testWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitesting") else { return }
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentViewController: NSHostingController(rootView: MenuBarView(state: state)))
        window.title = "PDF Compressor"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        testWindow = window
        NSApp.activate(ignoringOtherApps: true)
        if let index = args.firstIndex(of: "--input"), args.indices.contains(index + 1) {
            state.importPDF(URL(fileURLWithPath: args[index + 1]))
        } else if let index = args.firstIndex(of: "--fixture"), args.indices.contains(index + 1),
                  let url = Bundle.main.url(forResource: args[index + 1], withExtension: "pdf", subdirectory: "Fixtures") {
            state.importPDF(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { state.terminate() }
}

@main
struct PDFCompressorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("PDF Compressor", systemImage: "doc.zipper") {
            MenuBarView(state: delegate.state)
        }
        .menuBarExtraStyle(.window)
    }
}
