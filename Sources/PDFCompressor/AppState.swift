import AppKit
import PDFCompressorCore
import SwiftUI
import UniformTypeIdentifiers

let appDefaults: UserDefaults = {
    guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return .standard }
    let name = "com.pdfcompressor.ui-tests"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}()

@MainActor
final class AppState: ObservableObject {
    enum Phase { case idle, analyzing, ready, compressing, completed, failed }

    @Published var phase = Phase.idle
    @Published var info: PDFInfo?
    @Published var result: CompressionResult?
    @Published var preset = appDefaults.string(forKey: "defaultPreset") ?? "balanced"
    @Published var targetText = "1"
    @Published var targetUnit = appDefaults.string(forKey: "customUnit") ?? "MB"
    @Published var progress = 0.0
    @Published var progressMessage = "Preparing PDF…"
    @Published var errorMessage: String?
    @Published var alertMessage: String?
    @Published var savedURL: URL?
    @Published var showingSettings = false

    private var task: Task<Void, Never>?
    private var directory: URL?
    private var originalURL: URL?
    private var originalIdentity: FileIdentity?
    var busy: Bool { phase == .analyzing || phase == .compressing }

    var selectedPreset: CompressionPreset? {
        switch preset {
        case "light": return .light
        case "balanced": return .balanced
        case "strong": return .strong
        case "custom":
            guard let info, let bytes = targetBytes, bytes >= 1_024, bytes < info.originalBytes else { return nil }
            return .custom(targetBytes: bytes)
        default: return .balanced
        }
    }

    var targetBytes: Int64? {
        guard let info, let unit = SizeUnit(rawValue: targetUnit) else { return nil }
        let normalized = targetText.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        return try? TargetSize.bytes(from: normalized, unit: unit, originalBytes: info.originalBytes)
    }

    func choosePDF() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { importPDF(url) }
    }

    func importPDF(_ url: URL) {
        guard !busy else { return }
        reset()
        phase = .analyzing
        originalURL = url
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PDFCompressor-\(UUID().uuidString)", isDirectory: true)
        directory = temporary
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try PDFAnalyzer.analyze(url)
                let identity = try FileService.identity(of: url)
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                let snapshot = temporary.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: snapshot)
                let info = try PDFAnalyzer.analyze(snapshot)
                try Task.checkCancellation()
                await self?.importFinished(info, identity: identity)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                await self?.operationFailed(error)
            }
        }
    }

    private func importFinished(_ value: PDFInfo, identity: FileIdentity) {
        info = value
        originalIdentity = identity
        targetText = String(format: "%.4f", Double(max(1_024, value.originalBytes / 2)) / (targetUnit == "KB" ? 1_024 : 1_048_576))
        phase = .ready
        task = nil
    }

    func compress() {
        guard !busy, let info, let preset = selectedPreset, let directory else { return }
        phase = .compressing
        progress = 0
        progressMessage = "Preparing PDF…"
        errorMessage = nil
        let destination = directory.appendingPathComponent("result-\(UUID().uuidString).pdf")
        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await PDFCompressor().compress(source: info.sourceURL, destination: destination, preset: preset) { [self] value in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .compressing, self.task?.isCancelled != true else { return }
                        self.progress = value.fraction
                        self.progressMessage = value.message
                    }
                }
                try Task.checkCancellation()
                await self.compressionFinished(result)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                await self.operationFailed(error)
            }
        }
    }

    private func compressionFinished(_ value: CompressionResult) {
        result = value
        progress = 1
        phase = .completed
        task = nil
    }

    private func operationFailed(_ error: Error) {
        task = nil
        if error is CancellationError || (error as? CompressionError) == .cancelled {
            phase = info == nil ? .idle : .ready
        } else {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    func cancel() {
        progressMessage = "Cancelling after the current PDF pass…"
        task?.cancel()
    }

    func reset() {
        guard !busy else { return }
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        originalURL = nil
        originalIdentity = nil
        info = nil
        result = nil
        savedURL = nil
        errorMessage = nil
        phase = .idle
        preset = appDefaults.string(forKey: "defaultPreset") ?? "balanced"
        targetUnit = appDefaults.string(forKey: "customUnit") ?? "MB"
    }

    func save() {
        guard let result, let originalURL, let originalIdentity else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        let base = originalURL.deletingPathExtension().lastPathComponent
        let pattern = appDefaults.string(forKey: "filenamePattern") ?? "{name}-compressed"
        let proposed = pattern.replacingOccurrences(of: "{name}", with: base).replacingOccurrences(of: "{preset}", with: preset)
        let safeName = proposed.components(separatedBy: CharacterSet(charactersIn: "/\\:").union(.controlCharacters)).joined(separator: "-")
        panel.nameFieldStringValue = (safeName.isEmpty ? "\(base)-compressed" : safeName) + (safeName.lowercased().hasSuffix(".pdf") ? "" : ".pdf")
        switch appDefaults.string(forKey: "outputFolder") ?? "ask" {
        case "source": panel.directoryURL = originalURL.deletingLastPathComponent()
        case "last":
            if let path = appDefaults.string(forKey: "lastOutputFolder") { panel.directoryURL = URL(fileURLWithPath: path) }
        default: break
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let accessed = destination.startAccessingSecurityScopedResource()
        let originalAccessed = originalURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { destination.stopAccessingSecurityScopedResource() }
            if originalAccessed { originalURL.stopAccessingSecurityScopedResource() }
        }
        do {
            try FileService.save(result: result, to: destination, originalURL: originalURL, originalIdentity: originalIdentity)
            savedURL = destination
            appDefaults.set(destination.deletingLastPathComponent().path, forKey: "lastOutputFolder")
            if appDefaults.bool(forKey: "revealAfterSave") { reveal() }
        } catch { alertMessage = error.localizedDescription }
    }

    func openPDF() {
        guard let url = savedURL ?? result?.outputURL else { return }
        if !NSWorkspace.shared.open(url) { alertMessage = "The PDF could not be opened. Save a copy and try again." }
    }

    func reveal() {
        guard let savedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
    }

    func terminate() {
        task?.cancel()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
