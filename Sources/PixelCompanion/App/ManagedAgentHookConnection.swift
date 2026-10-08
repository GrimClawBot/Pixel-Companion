import Foundation
import PixelCompanionCore

/// Only deterministic app-owned subfolders are supported. Selected arbitrary
/// hook paths are never persisted, and no startup directory is created.
enum ManagedAgentHookConnection {
    static func directory(
        provider: AgentHookProvider,
        root: URL
    ) -> URL? {
        let appFolder = root.appendingPathComponent(
            "Pixel Companion", isDirectory: true
        )
        let eventsFolder = appFolder.appendingPathComponent(
            "Agent Events", isDirectory: true
        )
        let providerFolder = eventsFolder.appendingPathComponent(
            provider.directoryName, isDirectory: true
        )
        // Reject a redirected or group-accessible parent, even when the
        // final provider folder itself appears owner-private.
        guard AgentHookSetupPlan.validDirectory(appFolder),
              AgentHookSetupPlan.validDirectory(eventsFolder),
              AgentHookSetupPlan.validDirectory(providerFolder) else { return nil }
        return providerFolder
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
