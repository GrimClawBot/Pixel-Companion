import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Explicit opt-in to a locally selected status file; its path stays in RAM.
struct LocalInfrastructureSettingsControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: LocalInfrastructureMonitor

    var body: some View {
        Section {
            Toggle("Enable local infrastructure reports", isOn: $model.localInfrastructureEnabled)
                .accessibilityIdentifier("companion.settings.infrastructure-enabled")
            if model.localInfrastructureEnabled {
                HStack(spacing: 8) {
                    Button("Choose JSON report…", action: chooseFile)
                        .accessibilityIdentifier("companion.settings.infrastructure-file")
                    if monitor.isConnected {
                        Button("Disconnect", action: monitor.disconnect)
                            .accessibilityIdentifier("companion.settings.infrastructure-disconnect")
                    }
                    Spacer(minLength: 0)
                }
                Text(monitor.isConnected
                     ? "A local report file is selected for this app session."
                     : "No infrastructure report selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Infrastructure · optional local JSON")
        } footer: {
            Text("Choose a JSON file published by a source you trust. " +
                 "Pixel Companion reads only that selected local file; " +
                 "it never connects to VPS/HomeLab hosts or issues commands. " +
                 "The file path is forgotten at quit.")
        }
    }

    private func chooseFile() {
        guard model.localInfrastructureEnabled else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a trusted local infrastructure status JSON file."
        panel.prompt = "Connect"
        panel.begin { result in
            guard result == .OK, let file = panel.url else { return }
            Task { @MainActor in
                guard model.localInfrastructureEnabled else { return }
                monitor.connect(file)
            }
        }
    }
}
