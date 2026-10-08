import Foundation
import PixelCompanionCore

/// Only deterministic app-owned subfolders are supported. Selected arbitrary
/// hook paths are never persisted, and no startup directory is created.
enum ManagedAgentHookConnection {
    static func directory(
        provider: AgentHookProvider,
        root: URL
    ) -> URL? {
        let folder = root
            .appendingPathComponent("Pixel Companion", isDirectory: true)
            .appendingPathComponent("Agent Events", isDirectory: true)
            .appendingPathComponent(provider.directoryName, isDirectory: true)
        guard AgentHookSetupPlan.validDirectory(folder) else { return nil }
        return folder
    }

    @MainActor
    static func connect(
        settings: SettingsStore,
        codex: CodexTurnMonitor,
        claude: ClaudeHookMonitor,
        applicationSupportRoot: URL
    ) {
        guard settings.managedAgentHookAutoConnectEnabled else { return }
        if codex.enabled,
           let folder = directory(provider: .codex, root: applicationSupportRoot) {
            codex.connectDirectory(folder)
        }
        if claude.enabled,
           let folder = directory(provider: .claudeCode, root: applicationSupportRoot) {
            claude.connectDirectory(folder)
        }
    }
}
