import AppKit
import PixelCompanionCore
import SwiftUI

/// Sections remain independent: switching tabs never changes the connector or refresh cadence.
enum CompanionDetailTab: String, CaseIterable, Identifiable {
    case overview
    case agents
    case usage
    case activity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .agents: return "Agents"
        case .usage: return "Usage"
        case .activity: return "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .agents: return "person.2"
        case .usage: return "chart.bar"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

/// Data-independent shortcut routing; tiles never grant actions against Paperclip.
enum CompanionOverviewShortcut: String, CaseIterable {
    case agents
    case active
    case approvals

    var target: CompanionDetailTab {
        switch self {
        case .agents, .active: return .agents
        case .approvals: return .activity
        }
    }
}

/// A compact panel: status and controls stay visible while each section scrolls independently.
struct DetailContent: View {
    let snapshot: ConnectorSnapshot
    let mood: CharacterMood
    let openSettings: () -> Void
    var feedFreshness: FeedFreshness = .notApplicable
    var lastSuccessfulSync: Date?
    @Binding var selectedTab: CompanionDetailTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var agentUsageScope: AgentUsageScope = .all

    private func navigate(to tab: CompanionDetailTab) {
        withAnimation(CompanionMotion.tabTransition(reduceMotion: reduceMotion)) {
            selectedTab = tab
        }
    }

    private var canShowLive: Bool { feedFreshness.canPresentAsLive }
    private var liveSessions: [AgentSessionSnapshot] { canShowLive ? snapshot.agentSessions : [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SummaryHeader(
                snapshot: snapshot, mood: mood, feedFreshness: feedFreshness,
                lastSuccessfulSync: lastSuccessfulSync
            )
            tabBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let warning = feedFreshness.warning {
                        Label(warning, systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("companion.feed.warning")
                    }
                    tabContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
            }
            .accessibilityIdentifier("companion.detail.content")
            Divider()
            footer
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(CompanionDetailTab.allCases) { tab in
                Button {
                    navigate(to: tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(selectedTab == tab ? 0.18 : 0.04))
                    )
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: 24, height: 2)
                                .padding(.bottom, 1)
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label + " tab")
                .accessibilityValue(selectedTab == tab ? "Selected" : "Not selected")
                .accessibilityIdentifier("companion.tab." + tab.rawValue)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .overview: overviewContent
        case .agents: agentsContent
        case .usage: usageContent
        case .activity: activityContent
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                metric(value: canShowLive ? "\(snapshot.agentSessions.count)" : "—",
                       label: "Agents", shortcut: .agents)
                metric(value: canShowLive ? "\(liveSessions.filter(\.isActive).count)" : "—",
                       label: "Active", shortcut: .active)
                metric(value: canShowLive ? "\(snapshot.pendingApprovals.count)" : "—",
                       label: "Approvals", shortcut: .approvals)
            }
            SnapshotContent(
                snapshot: snapshot, mood: mood, approvalLimit: 2,
                feedFreshness: feedFreshness, lastSuccessfulSync: lastSuccessfulSync,
                showsHeader: false
            )
            Button("View usage details") { navigate(to: .usage) }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("companion.overview.usage")
            if canShowLive && snapshot.pendingApprovals.count > 2 {
                Button("View all approvals in Activity") { navigate(to: .activity) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
    }

    private func metric(
        value: String, label: String, shortcut: CompanionOverviewShortcut
    ) -> some View {
        Button {
            navigate(to: shortcut.target)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .companionCard()
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(label.lowercased())")
        .accessibilityIdentifier("companion.overview." + shortcut.rawValue)
    }

    private var agentsContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(text: AgentSessionPresentation.sectionTitle(liveSessions))
            if !canShowLive {
                Placeholder(text: "Live agent information is unavailable until Paperclip reconnects.")
            } else if liveSessions.isEmpty {
                Placeholder(text: "No agents reported by this connector.")
            } else {
                ForEach(liveSessions) { session in
                    AgentSessionRow(session: session)
                }
            }
        }
    }

    private var usageContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let usage = snapshot.usage, canShowLive {
                SectionTitle(text: "Company usage")
                UsageBar(usage: usage)
                Divider()
            }
            HStack {
                SectionTitle(text: "Agent usage · latest reported run")
                Spacer(minLength: 0)
                if canShowLive {
                    Text("\(liveSessions.filter(\.isActive).count) / \(liveSessions.count) active")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if canShowLive && !liveSessions.isEmpty {
                Picker("Agent usage filter", selection: $agentUsageScope) {
                    ForEach(AgentUsageScope.allCases, id: \.self) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .accessibilityIdentifier("companion.usage.filter")
                let visible = agentUsageScope.sessions(liveSessions)
                if visible.isEmpty {
                    Placeholder(text: "No active agents. Select All to see recent usage.")
                }
                ForEach(visible) { session in
                    AgentUsageCard(session: session)
                }
            } else {
                Placeholder(
                    text: canShowLive
                        ? "No agent usage reported yet."
                        : "Usage cannot be verified until Paperclip reconnects."
                )
            }
        }
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if canShowLive && !snapshot.pendingApprovals.isEmpty {
                HStack {
                    SectionTitle(text: "Pending approvals · read-only")
                    Spacer()
                    ApprovalCountBadge(count: snapshot.pendingApprovals.count)
                }
                ForEach(snapshot.pendingApprovals) { approval in
                    ApprovalRow(approval: approval)
                }
                Divider()
            }
            SectionTitle(text: canShowLive ? "Recent activity" : "Cached history")
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
