import AppKit
import PixelCompanionCore
import SwiftUI

/// Everything: snapshot, activity feed, recent messages and app controls.
struct DetailContent: View {
    let snapshot: ConnectorSnapshot
    let mood: CharacterMood
    let openSettings: () -> Void
    var feedFreshness: FeedFreshness = .notApplicable
    var lastSuccessfulSync: Date?
    @State private var agentUsageScope: AgentUsageScope = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SnapshotContent(
                snapshot: snapshot, mood: mood, approvalLimit: 0,
                feedFreshness: feedFreshness, lastSuccessfulSync: lastSuccessfulSync
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if feedFreshness.canPresentAsLive && !snapshot.agentSessions.isEmpty {
                        SectionTitle(text: AgentSessionPresentation.sectionTitle(snapshot.agentSessions))
                        ForEach(snapshot.agentSessions) { session in
                            AgentSessionRow(session: session)
                        }
                        Divider()
                        HStack {
                            SectionTitle(text: "Agent usage · latest reported run")
                            Spacer(minLength: 0)
                            Text(
                                "\(snapshot.agentSessions.filter(\.isActive).count) active / " +
                                    "\(snapshot.agentSessions.count)"
                            )
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Picker("Agent usage filter", selection: $agentUsageScope) {
                            ForEach(AgentUsageScope.allCases, id: \.self) { scope in
                                Text(scope.label).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        if agentUsageScope.sessions(snapshot.agentSessions).isEmpty {
                            Placeholder(text: "No active agents. Select All to see recent usage.")
                        }
                        ForEach(agentUsageScope.sessions(snapshot.agentSessions)) { session in
                            AgentUsageCard(session: session)
                            Divider()
                        }
                    }
                    if feedFreshness.canPresentAsLive && !snapshot.pendingApprovals.isEmpty {
                        HStack {
                            SectionTitle(text: "Pending approvals")
                            Spacer()
                            ApprovalCountBadge(count: snapshot.pendingApprovals.count)
                        }
                        ForEach(snapshot.pendingApprovals) { approval in
                            ApprovalRow(approval: approval)
                        }
                        Divider()
                    }
                    SectionTitle(text: feedFreshness.canPresentAsLive ? "Recent activity" : "Cached history")
                    let history = ActivityPresentation.history(
                        snapshot.recentActivity,
                        currentActivity: AgentSessionPresentation.highlightedActivity(
                            activity: snapshot.currentActivity,
                            sessions: snapshot.agentSessions
                        )
                    )
                    if history.isEmpty {
                        Placeholder(text: "No additional activity yet")
                    }
                    ForEach(history) { event in
                        ActivityRow(event: event)
                    }
                    if !snapshot.recentMessages.isEmpty {
                        SectionTitle(text: "Messages").padding(.top, 4)
                        ForEach(snapshot.recentMessages) { message in
                            MessageRow(message: message)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
    }

    private var footer: some View {
        HStack {
            Label("Read-only", systemImage: "eye")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Settings…", action: openSettings)
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}
