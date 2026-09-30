import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultPreset", store: appDefaults) private var defaultPreset = "balanced"
    @AppStorage("customUnit", store: appDefaults) private var customUnit = "MB"
    @AppStorage("filenamePattern", store: appDefaults) private var filenamePattern = "{name}-compressed"
    @AppStorage("outputFolder", store: appDefaults) private var outputFolder = "ask"
    @AppStorage("revealAfterSave", store: appDefaults) private var revealAfterSave = false
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Default compression", selection: $defaultPreset) {
                Text("Light").tag("light")
                Text("Balanced").tag("balanced")
                Text("Strong").tag("strong")
                Text("Custom").tag("custom")
            }.accessibilityIdentifier("defaultPreset")
            Picker("Target size unit", selection: $customUnit) {
                Text("KB").tag("KB")
                Text("MB").tag("MB")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Output filename").font(.callout)
                TextField("{name}-compressed", text: $filenamePattern).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("filenamePattern")
                Text("Use {name} for the original name and {preset} for the compression setting.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker("Start Save As in", selection: $outputFolder) {
                Text("System default").tag("ask")
                Text("Original PDF folder").tag("source")
                Text("Last saved folder").tag("last")
            }
            Toggle("Reveal in Finder after saving", isOn: $revealAfterSave)
            Text("Original files are never replaced. Every PDF stays on your Mac.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Done", action: done).buttonStyle(.borderedProminent).accessibilityIdentifier("settingsDone")
        }
    }
}
