import AppKit
import SwiftUI

/// Does not install hooks or alter the user's Codex configuration.
struct CodexTurnSettingsControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: CodexTurnMonitor

    var body: some View {
        Section {
            Toggle("Show Codex turn completions", isOn: $model.codexTurnEventsEnabled)
                .accessibilityIdentifier("companion.settings.codex-turn-events")
            if model.codexTurnEventsEnabled {
                HStack {
                    Button("Choose event folder…", action: chooseFolder)
                        .accessibilityIdentifier("companion.settings.codex-turn-file")
                    if monitor.isConnected {
                        Button("Disconnect", action: monitor.disconnect)
                            .accessibilityIdentifier("companion.settings.codex-turn-disconnect")
                    }
                    Spacer(minLength: 0)
                }
                Text(monitor.isConnected ? "Event folder connected for this session"
                     : "No event folder connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Codex turn completions")
        } footer: {
            Text("Requires a separately configured Codex notify hook. This app does not " +
                 "alter Codex settings, read conversations, or start agent tasks. " +
                 "Disabling the display does not uninstall an external hook.")
        }
    }

    private func chooseFolder() {
        guard model.codexTurnEventsEnabled else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for the privacy-scrubbed Codex turn-event JSON file."
        panel.prompt = "Connect"
        panel.begin { result in
            guard result == .OK, let file = panel.url else { return }
            Task { @MainActor in
                guard model.codexTurnEventsEnabled else { return }
                monitor.connectDirectory(file)
            }
        }
    }
}
