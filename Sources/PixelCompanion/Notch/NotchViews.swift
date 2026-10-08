import PixelCompanionCore
import SwiftUI

/// Panel sizes per surface. Compact mode stays within the physical notch width and adds a
/// short status strip below the camera housing, so adjacent menu-bar items remain untouched.
enum NotchLayout {
    static let compactBarHeight: CGFloat = 24
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
                    snapshot: model.snapshot, mood: model.mood, feedFreshness: model.feedFreshness
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

/// The compact status strip: character on the left, status on the right.
struct CompactBar: View {
    let snapshot: ConnectorSnapshot
    let mood: CharacterMood
    var feedFreshness: FeedFreshness = .notApplicable

    var body: some View {
        HStack {
            CharacterView(mood: mood, pixelSize: 2)
            Spacer()
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
            Image(systemName: mood.symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(mood.title)
        }
    }
}
