import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A user-led draft builder. The only side effects are picker selection,
/// an explicitly pressed Copy button, and an explicitly pressed Connect.
struct AgentHookGuidedSetupView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section {
            Text("Connect Codex and Claude Code without changing their configuration automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(
                "Reconnect my private Codex and Claude event folders at launch",
                isOn: $model.managedAgentHookAutoConnectEnabled
            )
            .accessibilityIdentifier("companion.setup.managed-auto-connect")
            Text("Only your verified private Pixel Companion Application Support folders. " +
                 "Custom folder selections remain session-only.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            AgentHookSetupSteps(provider: .codex, model: model)
            AgentHookSetupSteps(provider: .claudeCode, model: model)
        } header: {
            Text("Guided local agent setup")
        } footer: {
            Text("No hook is installed by Pixel Companion. Review existing configuration " +
                 "and merge the generated snippet yourself. Both hook scripts can receive " +
                 "private input, so only select trusted scripts. External hooks continue " +
                 "writing after you disable their in-app displays.")
        }
    }
}

private struct AgentHookSetupSteps: View {
    let provider: AgentHookProvider
    @ObservedObject var model: AppModel
    @State private var script: URL?
    @State private var directory: URL?
    @State private var copied = false
    @State private var folderError: String?

    private var snippet: String? {
        AgentHookSetupPlan.snippet(provider: provider, script: script, directory: directory)
    }

    var body: some View {
        DisclosureGroup(provider.title) {
            VStack(alignment: .leading, spacing: 9) {
                Text("1. Select the trusted bridge script from the Pixel Companion source.")
                    .font(.caption)
                Button("Choose \(provider.scriptName)…", action: chooseScript)
                    .accessibilityIdentifier("companion.setup." + provider.rawValue + ".script")
                choiceStatus(
                    selected: script,
                    valid: AgentHookSetupPlan.validScript(script, provider: provider),
                    missing: "No trusted bridge script selected"
                )

                Text("2. Choose an existing private folder (owned by you, with no group access).")
                    .font(.caption)
                HStack {
                    Button("Create private event folder", action: createPrivateFolder)
                        .accessibilityIdentifier("companion.setup." + provider.rawValue + ".create")
                    Button("Choose existing…", action: chooseDirectory)
                        .accessibilityIdentifier("companion.setup." + provider.rawValue + ".folder")
                }
                if let folderError {
                    Text(folderError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                choiceStatus(
                    selected: directory,
                    valid: AgentHookSetupPlan.validDirectory(directory),
                    missing: "No private event folder selected"
                )

                Text("3. Review and merge this snippet into \(provider.configurationName).")
                    .font(.caption)
                if let snippet {
                    ScrollView(.vertical) {
                        Text(snippet)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(maxHeight: 110)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    Button(copied ? "Copied config draft" : "Copy config draft") {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(snippet, forType: .string)
                    }
                    .accessibilityIdentifier("companion.setup." + provider.rawValue + ".copy")
                    Text(provider == .codex
                         ? "Codex supports one notify command. Do not overwrite an existing one. " +
                           "CLI notification support in IDE sessions is not guaranteed."
                         : "Merge new event hooks with existing hooks; do not replace other settings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Connect read-only display in Pixel Companion") {
                        connectInApp()
                    }
                    .accessibilityIdentifier("companion.setup." + provider.rawValue + ".connect")
                    Text("Connecting the display does NOT install or activate the external hook.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Choose the correct script and a private folder before a draft is available.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 5)
        }
        .onChange(of: script) { copied = false }
        .onChange(of: directory) { copied = false }
    }

    @ViewBuilder
    private func choiceStatus(selected: URL?, valid: Bool, missing: String) -> some View {
        Text(selected == nil ? missing : (valid ? "Validated for draft generation" :
                                             "Invalid selection or insufficient privacy permissions"))
            .font(.caption2)
            .foregroundStyle(valid ? Color.secondary : Color.orange)
    }

    private func createPrivateFolder() {
        do {
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            directory = try AgentHookSetupPlan.preparePrivateDirectory(
                provider: provider, root: root
            )
            folderError = nil
        } catch {
            folderError = "Could not create a private folder. No hook was installed."
        }
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.pythonScript, UTType.plainText]
        panel.message = "Choose the trusted \(provider.scriptName) from Pixel Companion."
        let sourceScripts = Bundle.main.bundleURL.deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts", isDirectory: true)
        if FileManager.default.fileExists(atPath: sourceScripts.path) {
            panel.directoryURL = sourceScripts
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            script = url
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose an existing private local folder for agent events."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            directory = url
            folderError = nil
        }
    }

    private func connectInApp() {
        guard snippet != nil, let directory else { return }
        switch provider {
        case .codex:
            model.codexTurnEventsEnabled = true
            model.codexTurnMonitor.connectDirectory(directory)
        case .claudeCode:
            model.claudeHookEventsEnabled = true
            model.claudeHookMonitor.connectDirectory(directory)
        }
    }
}
