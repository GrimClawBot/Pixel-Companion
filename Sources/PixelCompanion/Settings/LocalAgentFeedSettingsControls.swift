import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Explicit user-selected local-file transport, never an automatic scan of
/// Codex/Claude/Hermes histories. Selection exists only in RAM this launch.
struct LocalAgentFeedSettingsControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: LocalAgentFeedMonitor

    var body: some View {
        Section {
            Toggle("Enable local agent status", isOn: $model.localAgentFeedEnabled)
                .accessibilityIdentifier("companion.settings.local-agent-feed")
            if model.localAgentFeedEnabled {
                HStack {
                    Button("Choose status file…", action: chooseFile)
                        .accessibilityIdentifier("companion.settings.local-agent-file")
                    if monitor.isConnected {
                        Button("Disconnect", action: monitor.disconnect)
                            .accessibilityIdentifier("companion.settings.local-agent-disconnect")
                    }
                    Spacer()
                }
                Text(monitor.isConnected ? "Status file selected for this session"
                     : "No local status file selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Local agent sessions")
        } footer: {
            Text("For explicit JSON status feeds from Codex, Claude Code, Hermes or " +
                 "your own agents. No automatic process discovery, chat logs, or commands. " +
                 "The file connection is forgotten at quit.")
        }
    }

    private func chooseFile() {
        guard model.localAgentFeedEnabled else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a status JSON file published by a trusted local agent."
        panel.prompt = "Connect"
        panel.begin { result in
            guard result == .OK, let file = panel.url else { return }
            Task { @MainActor in
                guard model.localAgentFeedEnabled else { return }
                monitor.connect(file)
            }
        }
    }
}
