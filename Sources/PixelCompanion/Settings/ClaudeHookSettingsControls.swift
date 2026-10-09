import AppKit
import SwiftUI

/// An external Claude Code hook must be enabled deliberately by the human.
struct ClaudeHookSettingsControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: ClaudeHookMonitor

    var body: some View {
        Section {
            Toggle("Show Claude Code lifecycle events", isOn: $model.claudeHookEventsEnabled)
                .accessibilityIdentifier("companion.settings.claude-hook-events")
            if model.claudeHookEventsEnabled {
                HStack {
                    Button("Choose event folder…", action: chooseFolder)
                        .accessibilityIdentifier("companion.settings.claude-hook-folder")
                    if monitor.isConnected {
                        Button("Disconnect", action: monitor.disconnect)
                            .accessibilityIdentifier("companion.settings.claude-hook-disconnect")
                    }
                    Spacer(minLength: 0)
                }
                Text(monitor.isConnected ? "Event folder connected for this session"
                     : "No event folder connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Claude Code hooks")
        } footer: {
            Text("Requires separately configured Claude Code command hooks. " +
                 "No prompt or transcript access, no automatic settings changes or approval actions. " +
                 "Turning this display off does not uninstall an external hook.")
        }
    }

    private func chooseFolder() {
        guard model.claudeHookEventsEnabled else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a private folder for scrubbed Claude Code lifecycle events."
        panel.prompt = "Connect"
        panel.begin { result in
            guard result == .OK, let directory = panel.url else { return }
            Task { @MainActor in
                guard model.claudeHookEventsEnabled else { return }
                monitor.connectDirectory(directory)
            }
        }
    }
}
