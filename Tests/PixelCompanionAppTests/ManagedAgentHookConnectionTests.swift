import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

@MainActor
final class ManagedAgentHookConnectionTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let defaults: UserDefaults
        let settings: SettingsStore
    }

    private func fixture() throws -> Fixture {
        let suite = "ManagedAgentHook-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PC50-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return Fixture(root: root, defaults: defaults, settings: SettingsStore(defaults: defaults))
    }

    func testDefaultOffNeverConnectsOrCreatesFolders() throws {
        let fixture = try fixture()
        let (root, settings) = (fixture.root, fixture.settings)
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = CodexTurnMonitor(read: { _ in nil })
        let claude = ClaudeHookMonitor(read: { _ in nil })
        codex.configure(enabled: true)
        claude.configure(enabled: true)
        ManagedAgentHookConnection.connect(
            settings: settings, codex: codex, claude: claude,
            applicationSupportRoot: root
        )
        XCTAssertFalse(codex.isConnected)
        XCTAssertFalse(claude.isConnected)
        XCTAssertNil(ManagedAgentHookConnection.directory(provider: .codex, root: root))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Pixel Companion").path
        ))
        codex.configure(enabled: false)
        claude.configure(enabled: false)
    }

    func testEnabledOnlyConnectsExistingPrivateDirectories() throws {
        let fixture = try fixture()
        let (root, settings) = (fixture.root, fixture.settings)
        defer { try? FileManager.default.removeItem(at: root) }
        let codexFolder = try AgentHookSetupPlan.preparePrivateDirectory(
            provider: .codex, root: root
        )
        let claudeFolder = try AgentHookSetupPlan.preparePrivateDirectory(
            provider: .claudeCode, root: root
        )
        settings.managedAgentHookAutoConnectEnabled = true
        XCTAssertEqual(
            ManagedAgentHookConnection.directory(provider: .codex, root: root), codexFolder
        )
        XCTAssertEqual(
            ManagedAgentHookConnection.directory(provider: .claudeCode, root: root), claudeFolder
        )
        var codexReads = 0
        let codex = CodexTurnMonitor(read: { _ in codexReads += 1; return nil })
        let claude = ClaudeHookMonitor(read: { _ in nil })
        codex.configure(enabled: true)
        ManagedAgentHookConnection.connect(
            settings: settings, codex: codex, claude: claude,
            applicationSupportRoot: root
        )
        XCTAssertTrue(codex.isConnected)
        XCTAssertFalse(claude.isConnected)
        XCTAssertEqual(codexReads, 1)
        codex.configure(enabled: false)
    }

    func testInsecureFolderCannotAutoConnect() throws {
        let fixture = try fixture()
        let (root, settings) = (fixture.root, fixture.settings)
        defer { try? FileManager.default.removeItem(at: root) }
        let codexFolder = try AgentHookSetupPlan.preparePrivateDirectory(
            provider: .codex, root: root
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: codexFolder.path
        )
        settings.managedAgentHookAutoConnectEnabled = true
        let codex = CodexTurnMonitor(read: { _ in XCTFail("Unexpected read"); return nil })
        codex.configure(enabled: true)
        ManagedAgentHookConnection.connect(
            settings: settings, codex: codex, claude: ClaudeHookMonitor(),
            applicationSupportRoot: root
        )
        XCTAssertFalse(codex.isConnected)
        codex.configure(enabled: false)
    }

    func testSymlinkedAppParentDoesNotAutoConnect() throws {
        let fixture = try fixture()
        let (root, settings) = (fixture.root, fixture.settings)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try AgentHookSetupPlan.preparePrivateDirectory(
            provider: .codex, root: root
        )
        let parent = root.appendingPathComponent("Pixel Companion", isDirectory: true)
        let redirected = root.appendingPathComponent("MovedApp", isDirectory: true)
        try FileManager.default.moveItem(at: parent, to: redirected)
        try FileManager.default.createSymbolicLink(
            at: parent, withDestinationURL: redirected
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertNil(ManagedAgentHookConnection.directory(provider: .codex, root: root))
        settings.managedAgentHookAutoConnectEnabled = true
        let monitor = CodexTurnMonitor(read: { _ in
            XCTFail("Symlinked parent must never be read")
            return nil
        })
        monitor.configure(enabled: true)
        ManagedAgentHookConnection.connect(
            settings: settings, codex: monitor,
            claude: ClaudeHookMonitor(), applicationSupportRoot: root
        )
        XCTAssertFalse(monitor.isConnected)
        monitor.configure(enabled: false)
    }

    func testSymlinkedEventsParentDoesNotAutoConnect() throws {
        let fixture = try fixture()
        let root = fixture.root
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = try AgentHookSetupPlan.preparePrivateDirectory(
            provider: .claudeCode, root: root
        )
        let events = root.appendingPathComponent(
            "Pixel Companion/Agent Events", isDirectory: true
        )
        let redirected = root.appendingPathComponent("MovedEvents", isDirectory: true)
        try FileManager.default.moveItem(at: events, to: redirected)
        try FileManager.default.createSymbolicLink(
            at: events, withDestinationURL: redirected
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
        XCTAssertNil(ManagedAgentHookConnection.directory(
            provider: .claudeCode, root: root
        ))
    }

    func testInsecureParentModeDoesNotAutoConnect() throws {
        let fixture = try fixture()
        let root = fixture.root
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try AgentHookSetupPlan.preparePrivateDirectory(provider: .codex, root: root)
        let parent = root.appendingPathComponent("Pixel Companion", isDirectory: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: parent.path
        )
        XCTAssertNil(ManagedAgentHookConnection.directory(provider: .codex, root: root))
    }

    func testPrivateFullParentChainStillConnects() throws {
        let fixture = try fixture()
        let root = fixture.root
        defer { try? FileManager.default.removeItem(at: root) }
        for provider in AgentHookProvider.allCases {
            let destination = try AgentHookSetupPlan.preparePrivateDirectory(
                provider: provider, root: root
            )
            XCTAssertEqual(
                ManagedAgentHookConnection.directory(provider: provider, root: root),
                destination
            )
        }
    }

    func testPreferenceIndependentOfExistingOptions() throws {
        let fixture = try fixture()
        let settings = fixture.settings
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        XCTAssertFalse(settings.managedAgentHookAutoConnectEnabled)
        settings.managedAgentHookAutoConnectEnabled = true
        XCTAssertTrue(settings.managedAgentHookAutoConnectEnabled)
        XCTAssertFalse(settings.codexTurnEventsEnabled)
        XCTAssertFalse(settings.claudeHookEventsEnabled)
        settings.reset()
        XCTAssertFalse(settings.managedAgentHookAutoConnectEnabled)
    }
}
