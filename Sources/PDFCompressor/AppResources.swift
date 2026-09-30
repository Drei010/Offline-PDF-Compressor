import AppKit

enum AppResources {
    static let appIcon = image("AppIconPreview")
    static let menuBarIcon: NSImage = {
        let icon = image("MenuBarIconTemplate")
        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = true
        return icon
    }()

    private static func image(_ name: String) -> NSImage {
        var url = Bundle.main.url(forResource: name, withExtension: "png")
        #if SWIFT_PACKAGE
        if url == nil { url = Bundle.module.url(forResource: name, withExtension: "png") }
        #endif
        return NSImage(contentsOf: url!)!
    }
}
