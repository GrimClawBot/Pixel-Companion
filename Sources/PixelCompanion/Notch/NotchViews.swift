import PixelCompanionCore
import SwiftUI

/// Panel sizes per surface. Compact mode stays within the physical notch width and adds a
/// short status strip below the camera housing, so adjacent menu-bar items remain untouched.
enum NotchLayout {
    static let compactBarHeight: CGFloat = 32
    static let snapshotSize = CGSize(width: 400, height: 200)
    static let detailSize = CGSize(width: 440, height: 440)

    static func size(for surface: NotchSurface, notchSize: CGSize) -> CGSize {
        switch surface {
        case .compact:
            return CGSize(width: notchSize.width, height: notchSize.height + compactBarHeight)
        case .snapshot:
            return CGSize(
                width: max(snapshotSize.width, notchSize.width),
                height: snapshotSize.height + notchSize.height
            )
        case .detail:
            return CGSize(
                width: max(detailSize.width, notchSize.width),
                height: detailSize.height + notchSize.height
            )
        }
    }
}

/// What the notch view needs from its controller.
@MainActor
final class NotchViewState: ObservableObject {
    @Published var surface: NotchSurface = .compact
    @Published var notchSize = CGSize(width: 185, height: 32)
}

struct NotchRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: NotchViewState
    let onClick: () -> Void
    let openSettings: () -> Void

    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            if state.surface == .compact {
                Color.clear
                    .frame(height: state.notchSize.height)
                CompactBar(
                    snapshot: model.snapshot, mood: model.mood,
                    feedFreshness: model.feedFreshness, showsStatusText: true
                )
                    .frame(height: NotchLayout.compactBarHeight)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClick)
            } else {
                CompactBar(
                    snapshot: model.snapshot, mood: model.mood, feedFreshness: model.feedFreshness
                )
                    .frame(height: state.notchSize.height)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClick)
                expandedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius)
                .fill(Color.black)
        )
    }

    @ViewBuilder private var expandedContent: some View {
        switch state.surface {
        case .compact:
            EmptyView()
        case .snapshot:
            SnapshotContent(
                snapshot: model.snapshot, mood: model.mood,
                feedFreshness: model.feedFreshness,
                    agentFeedFreshness: model.agentFeedFreshness,
                lastSuccessfulSync: model.lastSuccessfulPaperclipSync
            )
                .padding([.horizontal, .bottom], 16)
                .padding(.top, 8)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClick)
        case .detail:
            DetailContent(
                snapshot: model.snapshot, mood: model.mood,
                openSettings: openSettings, feedFreshness: model.feedFreshness,
                agentFeedFreshness: model.agentFeedFreshness,
                lastSuccessfulSync: model.lastSuccessfulPaperclipSync,
                publicGitHubState: model.publicGitHubState,
                focusTimerEnabled: model.focusTimerEnabled,
                focusTimer: model.focusTimer,
                batteryHUDEnabled: model.batteryHUDEnabled,
                batteryMonitor: model.batteryMonitor,
                outputVolumeHUDEnabled: model.outputVolumeHUDEnabled,
                outputVolumeMonitor: model.outputVolumeMonitor,
                displayBrightnessHUDEnabled: model.displayBrightnessHUDEnabled,
                displayBrightnessMonitor: model.displayBrightnessMonitor,
                downloadHUDEnabled: model.downloadHUDEnabled,
                downloadMonitor: model.downloadMonitor,
                fileShelfEnabled: model.fileShelfEnabled,
                fileShelf: model.fileShelf,
                clipboardHistoryEnabled: model.clipboardHistoryEnabled,
                clipboardHistory: model.clipboardHistory,
                localAgentFeed: model.localAgentFeed,
                codexProcessMonitor: model.codexProcessMonitor,
                codexTurnMonitor: model.codexTurnMonitor,
                claudeHookMonitor: model.claudeHookMonitor,
                localActivityTimeline: model.localActivityTimeline,
                localAgentAttention: model.localAgentAttention,
                calendarWidgetEnabled: model.calendarWidgetEnabled,
                calendarShowTitles: model.calendarShowTitles,
                calendarMonitor: model.calendarMonitor,
                musicWidgetEnabled: model.musicWidgetEnabled,
                musicShowTrackDetails: model.musicShowTrackDetails,
                musicMonitor: model.musicMonitor,
                selectedTab: $model.selectedDetailTab
            )
                .padding([.horizontal, .bottom], 16)
                .padding(.top, 8)
        }
    }
}

/// Shows the true source status even when a prior working mood has gone stale.
enum CompactBarPresentation {
    static func displayMood(mood: CharacterMood, feedFreshness: FeedFreshness) -> CharacterMood {
        feedFreshness.canPresentAsLive ? mood : .offline
    }

    static func status(mood: CharacterMood, feedFreshness: FeedFreshness) -> String {
        switch feedFreshness {
        case .connecting: return "Connecting"
        case .stale: return "Updates delayed"
        case .unavailable: return "Disconnected"
        case .current, .notApplicable: return mood.title
        }
    }

    static func indicator(mood: CharacterMood, feedFreshness: FeedFreshness) -> String {
        switch feedFreshness {
        case .connecting: return "arrow.triangle.2.circlepath"
        case .stale: return "wifi.exclamationmark"
        case .unavailable: return "wifi.slash"
        case .current, .notApplicable: return mood.symbolName
        }
    }
}

/// The compact status strip: bigger pixel character with an honest status label.
struct CompactBar: View {
    let snapshot: ConnectorSnapshot
    let mood: CharacterMood
    var feedFreshness: FeedFreshness = .notApplicable
    var showsStatusText = false

    private var label: String {
        CompactBarPresentation.status(mood: mood, feedFreshness: feedFreshness)
    }

    var body: some View {
        HStack(spacing: 6) {
            CharacterView(
                mood: CompactBarPresentation.displayMood(mood: mood, feedFreshness: feedFreshness),
                pixelSize: 2.6
            )
                .accessibilityHidden(showsStatusText)
            if showsStatusText {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Companion status: " + label)
            }
            Spacer(minLength: 0)
            trailingIndicator
        }
    }

    @ViewBuilder private var trailingIndicator: some View {
        if feedFreshness.canPresentAsLive && !snapshot.pendingApprovals.isEmpty {
            Text("\(snapshot.pendingApprovals.count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .background(Capsule().fill(Color.orange))
                .accessibilityLabel("\(snapshot.pendingApprovals.count) waiting for approval")
        } else {
            Image(systemName: CompactBarPresentation.indicator(
                mood: mood, feedFreshness: feedFreshness
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(label)
        }
    }
}
