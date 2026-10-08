import Darwin
import Foundation

/// A draft is not a hook installation. The only generated output is text
/// which the user can copy and manually merge into their existing settings.
enum AgentHookProvider: String, CaseIterable, Identifiable {
    case codex
    case claudeCode

    var id: Self { self }

    var title: String {
        switch self {
        case .codex: "Codex CLI"
        case .claudeCode: "Claude Code"
        }
    }

    var scriptName: String {
        switch self {
        case .codex: "codex_notify_bridge.py"
        case .claudeCode: "claude_hook_bridge.py"
        }
    }

    var directoryName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }

    var configurationName: String {
        switch self {
        case .codex: "~/.codex/config.toml"
        case .claudeCode: "~/.claude/settings.json"
        }
    }
}

enum AgentHookSetupPlan {
    static let maxPathBytes = 1_024
    static let claudeEvents = [
        "SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"
    ]

    /// Validation is metadata only: never read any chosen Python script.
    /// A malicious file can mimic the correct name, so the user must select
    /// ONLY a known trusted copy from the Pixel Companion source checkout.
    static func validScript(_ url: URL?, provider: AgentHookProvider) -> Bool {
        guard let url, validPath(url), url.lastPathComponent == provider.scriptName,
              let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]),
              values.isRegularFile == true, values.isSymbolicLink != true
        else { return false }
        return true
    }

    /// Require a real user-owned, private directory before offering any
    /// copyable configuration. Script path, folder and config are NEVER saved.
    static func validDirectory(_ url: URL?) -> Bool {
        guard let url, validPath(url),
              let values = try? url.resourceValues(forKeys: [
                  .isSymbolicLinkKey, .isDirectoryKey
              ]),
              values.isDirectory == true, values.isSymbolicLink != true,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let owner = attributes[.ownerAccountID] as? NSNumber,
              let permissions = attributes[.posixPermissions] as? NSNumber
        else { return false }
        return owner.uint32Value == getuid()
            && (permissions.intValue & 0o077) == 0
    }

    /// Explicit user action only; creates private folders under the supplied
    /// application-support root without replacing any existing path.
    static func preparePrivateDirectory(
        provider: AgentHookProvider, root: URL
    ) throws -> URL {
        let parent = root.appendingPathComponent("Pixel Companion", isDirectory: true)
        let events = parent.appendingPathComponent("Agent Events", isDirectory: true)
        let destination = events.appendingPathComponent(provider.directoryName, isDirectory: true)
        for url in [parent, events, destination] {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(
                    at: url, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            guard validDirectory(url) else {
                throw CocoaError(.fileReadNoPermission)
            }
        }
        return destination
    }

    private static func validPath(_ url: URL) -> Bool {
        guard url.isFileURL, url.path.hasPrefix("/"),
              !url.path.isEmpty, url.path.utf8.count <= maxPathBytes else { return false }
        return url.path.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !(0x202A...0x202E).contains(scalar.value)
                && !(0x2066...0x2069).contains(scalar.value)
                && scalar.value != 0x200E && scalar.value != 0x200F
        }
    }

    static func snippet(
        provider: AgentHookProvider,
        script: URL?,
        directory: URL?
    ) -> String? {
        guard validScript(script, provider: provider), validDirectory(directory),
              let script, let directory else { return nil }
        switch provider {
        case .codex:
            let parts = ["/usr/bin/python3", script.path, "--directory", directory.path]
            let quoted = parts.compactMap(jsonString)
            guard quoted.count == parts.count else { return nil }
            return "notify = [" + quoted.joined(separator: ", ") + "]"
        case .claudeCode:
            let command = ["/usr/bin/python3", script.path, "--directory", directory.path]
                .map(shellQuote).joined(separator: " ")
            let hooks = Dictionary(uniqueKeysWithValues: claudeEvents.map { name in
                (name, [["hooks": [["type": "command", "command": command]]]])
            })
            let document: [String: Any] = ["hooks": hooks]
            guard let json = try? JSONSerialization.data(
                withJSONObject: document, options: [.prettyPrinted, .sortedKeys]
            ) else { return nil }
            return String(data: json, encoding: .utf8)
        }
    }

    private static func jsonString(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value, options: [.fragmentsAllowed]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// POSIX shell single quotes: untrusted paths are always literal command
    /// arguments, never executed or interpreted by Pixel Companion.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
