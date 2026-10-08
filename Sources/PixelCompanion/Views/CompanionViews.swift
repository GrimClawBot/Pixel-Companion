import AppKit
import PixelCompanionCore
import SwiftUI

/// Character, mood and connection line. Shared by the notch and the menu-bar popover.
struct SummaryHeader: View {
    let snapshot: ConnectorSnapshot
    let mood: CharacterMood
    var feedFreshness: FeedFreshness = .notApplicable
    var lastSuccessfulSync: Date?

    var body: some View {
        HStack(spacing: 12) {
            CharacterView(mood: mood, pixelSize: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(mood.title)
                    .font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let lastSuccessfulSync {
                    HStack(spacing: 3) {
                        Text("Last synced")
                        Text(lastSuccessfulSync, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var statusLine: String {
        switch feedFreshness {
        case .stale: return "Paperclip · Updates delayed"
        case .unavailable: return "Paperclip · Connection unavailable"
        case .connecting, .current, .notApplicable: break
        }
        if let error = snapshot.lastError {
            return "\(snapshot.connectorName) · \(error)"
        }
        return "\(snapshot.connectorName) · \(snapshot.connectionState.displayName)"
    }
}

/// Current activity, pending approvals and usage: what hovering the notch shows.
struct SnapshotContent: View {
    let snapshot: ConnectorSnapshot
    let mood: CharacterMood
    var approvalLimit: Int? = 2
    var feedFreshness: FeedFreshness = .notApplicable
    var lastSuccessfulSync: Date?
    var showsHeader = true

    private var visibleApprovals: [ApprovalRequest] {
        ApprovalPresentation.visible(snapshot.pendingApprovals, limit: approvalLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                SummaryHeader(
                    snapshot: snapshot, mood: mood, feedFreshness: feedFreshness,
                    lastSuccessfulSync: lastSuccessfulSync
                )
                if let warning = feedFreshness.warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if feedFreshness.canPresentAsLive {
                liveContent
            }
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch AgentSessionPresentation.snapshotPrimary(
                activity: snapshot.currentActivity,
                sessions: snapshot.agentSessions
            ) {
            case let .activity(activity):
                SectionTitle(text: "Now")
                ActivityRow(event: activity, emphasizesTitle: true)
            case let .session(session):
                SectionTitle(text: session.isActive ? "Live agent" : "Recent agent")
                AgentSessionRow(session: session, compact: true)
            case nil:
                EmptyView()
            }
            if !visibleApprovals.isEmpty {
                HStack {
                    SectionTitle(text: "Waiting on you")
                    Spacer()
                    ApprovalCountBadge(count: snapshot.pendingApprovals.count)
                }
                ForEach(visibleApprovals) { approval in
                    ApprovalRow(approval: approval)
                }
            }
            if let usage = snapshot.usage {
                UsageBar(usage: usage)
            }
        }
    }
}

struct ActivityRow: View {
    let event: ActivityEvent
    var emphasizesTitle = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(emphasizesTitle ? .callout.weight(.semibold) : .callout)
                    .lineLimit(1)
                if let detail = event.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var symbol: String {
        switch event.kind {
        case .note: return "info.circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .note: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

struct ApprovalRow: View {
    let approval: ApprovalRequest

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(approval.title)
                .font(.callout)
                .lineLimit(1)
                .accessibilityLabel(ApprovalPresentation.accessibilityContext(approval))
            Spacer(minLength: 0)
            if ApprovalPresentation.showsTimestamp(approval) {
                Text(approval.requestedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ApprovalCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange))
            .accessibilityLabel(ApprovalPresentation.countLabel(count))
    }
}

struct UsageBar: View {
    let usage: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Usage · \(usage.periodLabel)")
                Spacer()
                Text(amount)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let fraction = usage.fractionUsed {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(fraction > 0.9 ? Color.orange : Color.accentColor)
            }
        }
    }

    private var amount: String {
        UsagePresentation.amount(usage)
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.role == .user ? "person.fill" : "bubble.left.fill")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(message.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct Placeholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
    }
}

enum ApprovalPresentation {
    static func visible(
        _ approvals: [ApprovalRequest],
        limit: Int?
    ) -> [ApprovalRequest] {
        guard let limit else { return approvals }
        return Array(approvals.prefix(max(limit, 0)))
    }

    static func countLabel(_ count: Int) -> String {
        "\(count) pending \(count == 1 ? "approval" : "approvals")"
    }

    static func accessibilityContext(_ approval: ApprovalRequest) -> String {
        "Waiting for approval: \(approval.title)"
    }

    static func showsTimestamp(_ approval: ApprovalRequest) -> Bool {
        approval.requestedAt != .distantPast
    }
}

enum ActivityPresentation {
    static func history(
        _ events: [ActivityEvent],
        currentActivity: ActivityEvent?
    ) -> [ActivityEvent] {
        guard let currentActivity, let index = events.firstIndex(of: currentActivity) else {
            return events
        }
        var history = events
        history.remove(at: index)
        return history
    }
}

enum UsagePresentation {
    static func amount(_ usage: UsageSnapshot) -> String {
        if usage.unit.lowercased() == "cents" {
            let used = currency(cents: usage.used)
            guard let limit = usage.limit else { return used }
            return "\(used) / \(currency(cents: limit))"
        }
        guard let limit = usage.limit else { return "\(usage.used) \(usage.unit)" }
        return "\(usage.used) / \(limit) \(usage.unit)"
    }

    private static func currency(cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let absolute = cents.magnitude
        let dollars = absolute / 100
        let remainder = absolute % 100
        return "\(sign)$\(dollars).\(String(format: "%02d", remainder))"
    }
}
