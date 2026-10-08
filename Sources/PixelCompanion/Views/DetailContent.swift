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

    /// Fixed keyboard shortcuts keep destinations predictable across display modes.
    var keyboardNumber: Character {
        switch self {
        case .overview: return "1"
        case .agents: return "2"
        case .usage: return "3"
        case .activity: return "4"
        }
    }

    /// Arrow navigation stops at either end rather than unexpectedly wrapping.
    func moving(by offset: Int) -> CompanionDetailTab {
        let tabs = Self.allCases
        guard let index = tabs.firstIndex(of: self) else { return self }
        let target = min(max(index + offset, 0), tabs.count - 1)
        return tabs[target]
    }

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
    var publicGitHubState: GitHubPublicState = .off
    var focusTimerEnabled = false
    var focusTimer: FocusTimerController?
    var batteryHUDEnabled = false
    var batteryMonitor: BatteryPowerMonitor?
    var outputVolumeHUDEnabled = false
    var outputVolumeMonitor: OutputVolumeMonitor?
    var displayBrightnessHUDEnabled = false
    var displayBrightnessMonitor: DisplayBrightnessMonitor?
    var downloadHUDEnabled = false
    var downloadMonitor: DownloadProgressMonitor?
    var fileShelfEnabled = false
    var fileShelf: TransientFileShelf?
    var clipboardHistoryEnabled = false
    var clipboardHistory: TransientClipboardHistory?
    var localAgentFeed: LocalAgentFeedMonitor?
    var codexProcessMonitor: CodexProcessMonitor?
    var codexTurnMonitor: CodexTurnMonitor?
    var calendarWidgetEnabled = false
    var calendarShowTitles = false
    var calendarMonitor: CalendarNextEventMonitor?
    var musicWidgetEnabled = false
    var musicShowTrackDetails = false
    var musicMonitor: MusicNowPlayingMonitor?
    @Binding var selectedTab: CompanionDetailTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var agentUsageScope: AgentUsageScope = .all
    @State private var selectedAgentID: String?

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
            CompanionTabBar(selectedTab: $selectedTab, reduceMotion: reduceMotion)
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
            // Switching tabs creates a fresh scroll position and a predictable reading start.
            .id(selectedTab)
            .accessibilityIdentifier("companion.detail.content")
            Divider()
            footer
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .overview: overviewContent
        case .agents: agentsContent
        case .usage: usageContent
        case .activity: activityContent
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
        VStack(alignment: .leading, spacing: 10) {
            if let codexProcessMonitor, codexProcessMonitor.enabled {
                CodexProcessView(monitor: codexProcessMonitor)
            }
            if let codexTurnMonitor, codexTurnMonitor.enabled {
                CodexTurnView(monitor: codexTurnMonitor)
            }
            if let localAgentFeed, localAgentFeed.enabled {
                LocalAgentSessionsView(monitor: localAgentFeed)
            }
            AgentsDirectoryView(
                sessions: liveSessions,
                isLive: canShowLive,
                tasks: canShowLive ? snapshot.tasks : [],
                selectedAgentID: $selectedAgentID
            )
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
            CompanyTasksView(
                tasks: canShowLive ? snapshot.tasks : [],
                agents: liveSessions, isLive: canShowLive,
                onSelectAgent: { agentID in
                    selectedAgentID = agentID
                    navigate(to: .agents)
                }
            )
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
            ActivityTimelineView(
                events: ActivityPresentation.history(
                    snapshot.recentActivity,
                    currentActivity: AgentSessionPresentation.highlightedActivity(
                        activity: snapshot.currentActivity,
                        sessions: snapshot.agentSessions
                    )
                ),
                isLive: canShowLive
            )
            if !snapshot.recentMessages.isEmpty {
                SectionTitle(text: "Messages").padding(.top, 4)
                ForEach(snapshot.recentMessages) { message in
                    MessageRow(message: message)
                }
            }
        }
    }
}

extension DetailContent {
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
            LiveActivityDigestView(snapshot: snapshot, isLive: canShowLive)
            PublicGitHubPulseView(state: publicGitHubState)
            LiveOperationsPulseView(
                sessions: liveSessions,
                pendingApprovalCount: snapshot.pendingApprovals.count,
                isLive: canShowLive,
                onSelectAgent: { agentID in
                    selectedAgentID = agentID
                    navigate(to: .agents)
                },
                onShowApprovals: { navigate(to: .activity) }
            )
            OperationalAttentionView(
                sessions: liveSessions,
                isLive: canShowLive,
                onSelectAgent: { agentID in
                    selectedAgentID = agentID
                    navigate(to: .agents)
                }
            )
            if focusTimerEnabled, let focusTimer {
                FocusTimerView(controller: focusTimer)
            }
            if batteryHUDEnabled, let batteryMonitor {
                BatteryPowerView(monitor: batteryMonitor)
            }
            if outputVolumeHUDEnabled, let outputVolumeMonitor {
                OutputVolumeView(monitor: outputVolumeMonitor)
            }
            if displayBrightnessHUDEnabled, let displayBrightnessMonitor {
                DisplayBrightnessView(monitor: displayBrightnessMonitor)
            }
            if downloadHUDEnabled, let downloadMonitor {
                DownloadProgressView(monitor: downloadMonitor)
            }
            if fileShelfEnabled, let fileShelf {
                TransientFileShelfView(shelf: fileShelf)
            }
            if clipboardHistoryEnabled, let clipboardHistory {
                TransientClipboardHistoryView(history: clipboardHistory)
            }
            if calendarWidgetEnabled, let calendarMonitor {
                CalendarNextEventView(
                    monitor: calendarMonitor, showTitles: calendarShowTitles
                )
            }
            if musicWidgetEnabled, let musicMonitor {
                MusicNowPlayingView(
                    monitor: musicMonitor, showDetails: musicShowTrackDetails
                )
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
