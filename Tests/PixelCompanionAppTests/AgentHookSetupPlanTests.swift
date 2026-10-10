import Foundation
@testable import PixelCompanion
import XCTest

final class AgentHookSetupPlanTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let codexScript: URL
        let claudeScript: URL
        let events: URL
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PC47-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let codex = root.appendingPathComponent("codex_notify_bridge.py")
        let claude = root.appendingPathComponent("claude_hook_bridge.py")
        try Data("trusted fixture".utf8).write(to: codex)
        try Data("trusted fixture".utf8).write(to: claude)
        let events = try AgentHookSetupPlan.preparePrivateDirectory(
            provider: .codex, root: root
        )
        return Fixture(root: root, codexScript: codex, claudeScript: claude, events: events)
    }

    func testGeneratesNoConfigurationWithoutBothExplicitChoices() throws {
        let chosen = try fixture()
        defer { try? FileManager.default.removeItem(at: chosen.root) }
        XCTAssertNil(AgentHookSetupPlan.snippet(
            provider: .codex, script: nil, directory: chosen.events
        ))
        XCTAssertNil(AgentHookSetupPlan.snippet(
            provider: .codex, script: chosen.codexScript, directory: nil
        ))
        XCTAssertNil(AgentHookSetupPlan.snippet(
            provider: .claudeCode, script: chosen.codexScript, directory: chosen.events
        ))
    }

    func testCodexTOMLConfigIsSafelyQuotedAndComplete() throws {
        let chosen = try fixture()
        defer { try? FileManager.default.removeItem(at: chosen.root) }
        let draft = try XCTUnwrap(AgentHookSetupPlan.snippet(
            provider: .codex, script: chosen.codexScript, directory: chosen.events
        ))
        XCTAssertTrue(draft.hasPrefix("notify = ["))
        let arrayText = String(draft.dropFirst("notify = ".count))
        let values = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(arrayText.utf8)) as? [String]
        )
        XCTAssertEqual(values, [
            "/usr/bin/python3", chosen.codexScript.path, "--directory", chosen.events.path
        ])
        XCTAssertFalse(draft.contains("input-messages"))
        XCTAssertFalse(draft.contains("thread-id"))
        XCTAssertFalse(draft.contains("sudo"))
    }

    func testClaudeConfigIsValidJSONWithSupportedEventsOnly() throws {
        let chosen = try fixture()
        defer { try? FileManager.default.removeItem(at: chosen.root) }
        let draft = try XCTUnwrap(AgentHookSetupPlan.snippet(
            provider: .claudeCode, script: chosen.claudeScript, directory: chosen.events
        ))
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(draft.utf8)) as? [String: Any]
        )
        let hooks = try XCTUnwrap(document["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(AgentHookSetupPlan.claudeEvents))
        XCTAssertFalse(draft.contains("PermissionRequest"))
        XCTAssertFalse(draft.contains("PreToolUse"))
        XCTAssertTrue(draft.contains("claude_hook_bridge.py"))
        XCTAssertTrue(draft.contains("--directory"))
    }

    func testSingleQuoteDollarAndBacktickAreAlwaysShellLiteral() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PC47-'$HOME;`whoami`-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("claude_hook_bridge.py")
        try Data("test".utf8).write(to: script)
        let folder = try AgentHookSetupPlan.preparePrivateDirectory(
            provider: .claudeCode, root: root
        )
        let result = try XCTUnwrap(AgentHookSetupPlan.snippet(
            provider: .claudeCode, script: script, directory: folder
        ))
        XCTAssertTrue(result.contains("'\\\\''"))
        XCTAssertTrue(result.contains("$HOME"))
        XCTAssertTrue(result.contains("whoami"))
        XCTAssertFalse(result.contains("eval "))
        XCTAssertEqual(AgentHookSetupPlan.shellQuote("O'Reilly"), "'O'\\''Reilly'")
    }

    func testInsecureDirectoryCannotGenerateConfig() throws {
        let chosen = try fixture()
        defer { try? FileManager.default.removeItem(at: chosen.root) }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: chosen.events.path
        )
        XCTAssertFalse(AgentHookSetupPlan.validDirectory(chosen.events))
        XCTAssertNil(AgentHookSetupPlan.snippet(
            provider: .codex, script: chosen.codexScript, directory: chosen.events
        ))
    }

    func testSymlinkFolderAndScriptAreRejected() throws {
        let chosen = try fixture()
        defer { try? FileManager.default.removeItem(at: chosen.root) }
        let link = chosen.root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: chosen.events)
        XCTAssertFalse(AgentHookSetupPlan.validDirectory(link))
        let scriptLink = chosen.root.appendingPathComponent("codex_notify_bridge_link.py")
        try FileManager.default.createSymbolicLink(
            at: scriptLink, withDestinationURL: chosen.codexScript
        )
        XCTAssertFalse(AgentHookSetupPlan.validScript(scriptLink, provider: .codex))
    }

    func testPrivateDirectoryCreatedOnlyByExplicitCall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PC47Create-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = root.appendingPathComponent(
            "Pixel Companion/Agent Events/Codex", isDirectory: true
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: expected.path))
        XCTAssertFalse(AgentHookSetupPlan.validDirectory(expected))
        let created = try AgentHookSetupPlan.preparePrivateDirectory(
            provider: .codex, root: root
        )
        XCTAssertEqual(created, expected)
        XCTAssertTrue(AgentHookSetupPlan.validDirectory(created))
        let again = try AgentHookSetupPlan.preparePrivateDirectory(
            provider: .codex, root: root
        )
        XCTAssertEqual(again, created)
    }

    func testFolderOwnerPermissionAndInvalidPathGuards() throws {
        let chosen = try fixture()
        defer { try? FileManager.default.removeItem(at: chosen.root) }
        XCTAssertTrue(AgentHookSetupPlan.validDirectory(chosen.events))
        XCTAssertTrue(AgentHookSetupPlan.validScript(chosen.codexScript, provider: .codex))
        XCTAssertFalse(AgentHookSetupPlan.validScript(chosen.codexScript, provider: .claudeCode))
        let url = URL(string: "https://example.com/codex_notify_bridge.py")!
        XCTAssertFalse(AgentHookSetupPlan.validScript(url, provider: .codex))
    }
}
