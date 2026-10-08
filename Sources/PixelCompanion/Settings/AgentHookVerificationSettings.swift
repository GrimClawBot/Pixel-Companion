import SwiftUI

/// Guided verification never changes Codex/Claude settings or writes markers.
/// The user must independently trigger a real provider hook notification.
struct AgentHookVerificationSettings: View {
    @ObservedObject var codex: CodexTurnMonitor
    @ObservedObject var claude: ClaudeHookMonitor
    @StateObject private var verifier = AgentHookVerifier()

    var body: some View {
        Section {
            Text("After configuring a hook, start a check, run one normal agent turn, " +
                 "then look for a NEW local marker. Old markers are never proof.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 10)) { context in
                VStack(alignment: .leading, spacing: 14) {
                    verificationRow(
                        source: .codex, connected: codex.isConnected,
                        state: verifier.state(for: .codex, at: context.date)
                    )
                    verificationRow(
                        source: .claude, connected: claude.isConnected,
                        state: verifier.state(for: .claude, at: context.date)
                    )
                }
            }
            Text("This confirms only that the selected local marker changed. " +
                 "It does NOT authenticate the process that wrote it, verify " +
                 "a successful task, or read chat content. Codex IDE sessions " +
                 "might not invoke the Codex CLI notify hook.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } header: {
            Text("Verify hook delivery")
        } footer: {
            Text("No synthetic events, provider commands, automatic hook installation " +
                 "or permission changes. Verification resets when you leave Settings.")
        }
        .onAppear { verifier.bind(codex: codex, claude: claude) }
        .onDisappear { verifier.stopAll() }
    }

    @ViewBuilder
    private func verificationRow(
        source: AgentHookCheckSource,
        connected: Bool,
        state: AgentHookCheckState
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(source.title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                if connected {
                    Text("Display connected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(description(for: state))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("companion.verify." + source.rawValue + ".status")
            let diagnostic = diagnostic(for: source, check: state, now: Date())
            Text(diagnostic.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("companion.verify." + source.rawValue + ".diagnostic")
            Text(diagnostic.nextStep)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                Button("Start check") { start(source) }
                    .disabled(!connected)
                    .accessibilityIdentifier("companion.verify." + source.rawValue + ".start")
                Button("Check now") { refresh(source) }
                    .disabled(!connected)
                    .accessibilityIdentifier("companion.verify." + source.rawValue + ".refresh")
                if case .waiting = state {
                    Button("Cancel") { verifier.stop(source) }
                        .accessibilityIdentifier("companion.verify." + source.rawValue + ".cancel")
                }
            }
            .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }

    private func start(_ source: AgentHookCheckSource) {
        switch source {
        case .codex: verifier.start(codex: codex)
        case .claude: verifier.start(claude: claude)
        }
    }

    private func refresh(_ source: AgentHookCheckSource) {
        switch source {
        case .codex: codex.refresh()
        case .claude: claude.refresh()
        }
    }

    private func diagnostic(
        for source: AgentHookCheckSource,
        check: AgentHookCheckState,
        now: Date
    ) -> AgentHookDiagnostic {
        switch source {
        case .codex:
            return AgentHookDiagnosticGuide.codex(status: codex.status, check: check, now: now)
        case .claude:
            return AgentHookDiagnosticGuide.claude(status: claude.status, check: check, now: now)
        }
    }

    private func description(for state: AgentHookCheckState) -> String {
        switch state {
        case .notStarted:
            "Not checked. Start only after connecting a private event folder."
        case .needsSetup:
            "Needs setup: enable and connect the appropriate read-only display."
        case .waiting:
            "Waiting for a new valid event marker. Trigger an actual agent turn."
        case .observed:
            "New marker observed after check started. Source authenticity not verified."
        case .timedOut:
            "No new valid marker within 3 minutes. Review hook setup and try again."
        }
    }
}
