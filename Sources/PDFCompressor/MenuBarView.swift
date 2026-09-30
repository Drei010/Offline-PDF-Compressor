import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @ObservedObject var state: AppState
    @State private var dropTargeted = false
    private let accent = Color(red: 0.13, green: 0.49, blue: 0.43)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "doc.zipper").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PDF Compressor").font(.headline)
                    Text(state.showingSettings ? "Your preferences" : "Smaller files. All on your Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !state.showingSettings {
                    Button { state.showingSettings = true } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
                        .accessibilityIdentifier("settingsButton").disabled(state.busy)
                }
            }
            if state.showingSettings {
                SettingsView { state.showingSettings = false }
            } else {
                content
            }
            Divider()
            HStack {
                Label("100% offline", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 360)
        .tint(accent)
        .alert("Couldn’t complete the action", isPresented: Binding(get: { state.alertMessage != nil }, set: { if !$0 { state.alertMessage = nil } })) {
            Button("OK") { state.alertMessage = nil }
        } message: { Text(state.alertMessage ?? "") }
    }

    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle: dropZone
        case .analyzing:
            VStack(spacing: 16) {
                ProgressView()
                Text("Checking your PDF…").font(.headline)
                Button("Cancel", action: state.cancel).accessibilityIdentifier("cancelCompression")
            }.frame(maxWidth: .infinity).padding(.vertical, 38)
        case .ready: ready
        case .compressing: processing
        case .completed: completed
        case .failed:
            VStack(alignment: .leading, spacing: 14) {
                Label("Couldn’t process this PDF", systemImage: "exclamationmark.triangle")
                    .font(.headline).foregroundStyle(.orange)
                Text(state.errorMessage ?? "Please choose a different PDF.").font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("errorMessage")
                if state.info != nil {
                    Button("Try Again") { state.phase = .ready }.buttonStyle(.borderedProminent)
                }
                Button("Choose Another PDF", action: state.choosePDF).accessibilityIdentifier("choosePDF")
            }.padding(.vertical, 16)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.arrow.up").font(.system(size: 38, weight: .light)).foregroundStyle(accent)
            VStack(spacing: 5) {
                Text("Drop a PDF here").font(.title3.weight(.semibold))
                Text("Keep the content. Lose the extra size.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Choose PDF…", action: state.choosePDF)
                .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("choosePDF")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .background(accent.opacity(dropTargeted ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(dropTargeted ? 0.8 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            guard providers.count == 1, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in state.importPDF(url) }
            }
            return true
        }
        .accessibilityElement(children: .contain).accessibilityLabel("PDF drop zone")
    }

    private var fileSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").font(.title).foregroundStyle(accent)
                .frame(width: 44, height: 52).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(state.info?.fileName ?? "PDF").font(.headline).lineLimit(2).truncationMode(.middle)
                if let info = state.info {
                    Text("\(formatBytes(info.originalBytes)) · \(info.pageCount) \(info.pageCount == 1 ? "page" : "pages")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 18) {
            fileSummary
            VStack(alignment: .leading, spacing: 10) {
                Text("Compression").font(.subheadline.weight(.semibold))
                Picker("Compression", selection: $state.preset) {
                    Text("Light").tag("light")
                    Text("Balanced").tag("balanced")
                    Text("Strong").tag("strong")
                    Text("Custom").tag("custom")
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("presetPicker")
                if state.preset == "custom" {
                    HStack {
                        Text("Target size ≈").font(.callout)
                        TextField("Size", text: $state.targetText).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Target size").accessibilityIdentifier("customTarget")
                        Picker("Unit", selection: $state.targetUnit) {
                            Text("KB").tag("KB"); Text("MB").tag("MB")
                        }.labelsHidden().frame(width: 65).accessibilityIdentifier("targetUnit")
                    }
                    Text(state.selectedPreset == nil ? "Enter at least 1 KB, below the original size." : "We’ll find the best quality near your target. Exact sizes aren’t guaranteed (1 KB = 1,024 bytes).")
                        .font(.caption).foregroundStyle(state.selectedPreset == nil ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(presetDescription).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: state.compress) { Text("Compress PDF").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(state.selectedPreset == nil).accessibilityIdentifier("compressPDF")
            Button("Choose a different PDF", action: state.choosePDF)
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("choosePDF")
        }
    }

    private var presetDescription: String {
        switch state.preset {
        case "light": return "Gentle compression. Best for images you want to keep crisp."
        case "strong": return "Smaller images and files. Best for sharing on screen."
        default: return "A practical balance of image quality and file size."
        }
    }

    private var processing: some View {
        VStack(alignment: .leading, spacing: 20) {
            fileSummary
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Compressing…").font(.headline)
                    Spacer()
                    Text(state.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: state.progress).accessibilityLabel("Compression progress")
                Text(state.progressMessage).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Cancel", action: state.cancel).frame(maxWidth: .infinity).accessibilityIdentifier("cancelCompression")
        }.padding(.vertical, 10)
    }

    @ViewBuilder private var completed: some View {
        if let result = state.result {
            VStack(alignment: .leading, spacing: 16) {
                Label(result.isAlreadyOptimized ? "Already optimized" : "Compression complete", systemImage: result.isAlreadyOptimized ? "checkmark.seal" : "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(accent).accessibilityIdentifier("resultTitle")
                Text(state.info?.fileName ?? "PDF").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(alignment: .firstTextBaseline) {
                    Text(formatBytes(result.originalBytes)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.callout).foregroundStyle(.secondary)
                    Text(formatBytes(result.compressedBytes)).font(.title2.weight(.semibold))
                }
                if result.isAlreadyOptimized {
                    Text("This document could not be made smaller with these settings. Your original quality is preserved.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(Int(result.percentSaved.rounded()))% smaller · \(formatBytes(result.bytesSaved)) saved")
                        .font(.callout.weight(.medium)).foregroundStyle(accent)
                }
                if !result.targetReached {
                    Label("Target not reached. This is the smallest valid result from the available settings.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button(action: state.save) { Text(state.savedURL == nil ? "Save As…" : "Save Another Copy…").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("savePDF")
                HStack {
                    Button("Open PDF", action: state.openPDF).accessibilityIdentifier("openPDF")
                    Spacer()
                    Button("Show in Finder", action: state.reveal).disabled(state.savedURL == nil)
                        .help("Save your PDF to reveal it in Finder").accessibilityIdentifier("revealPDF")
                }
                if let savedURL = state.savedURL {
                    Label("Saved as \(savedURL.lastPathComponent)", systemImage: "checkmark")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).accessibilityIdentifier("savedMessage")
                }
                Button("Compress Another", action: state.reset).buttonStyle(.plain)
                    .font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("compressAnother")
            }
        }
    }
}
