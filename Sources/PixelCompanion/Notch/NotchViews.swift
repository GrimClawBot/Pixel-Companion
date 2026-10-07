import PixelCompanionCore
import SwiftUI

/// Panel sizes per surface. The compact surface is exactly the physical notch width so the
/// companion never overlays or intercepts adjacent menu-bar items. Expanded surfaces may grow
/// below and beyond the notch while the user is actively interacting with the companion.
enum NotchLayout {
    static let snapshotSize = CGSize(width: 400, height: 200)
    static let detailSize = CGSize(width: 440, height: 440)

    static func size(for surface: NotchSurface, notchSize: CGSize) -> CGSize {
        switch surface {
        case .compact:
            return notchSize
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
            CompactBar(snapshot: model.snapshot, mood: model.mood)
                .frame(height: state.notchSize.height)
                .padding(.horizontal, 12)
            expandedContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius)
                .fill(Color.black)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
    }

    @ViewBuilder private var expandedContent: some View {
        switch state.surface {
        case .compact:
            EmptyView()
        case .snapshot:
            SnapshotContent(snapshot: model.snapshot, mood: model.mood)
                .padding([.horizontal, .bottom], 16)
                .padding(.top, 8)
        case .detail:
            DetailContent(snapshot: model.snapshot, mood: model.mood, openSettings: openSettings)
                .padding([.horizontal, .bottom], 16)
                .padding(.top, 8)
        }
    }
}

/// The always-visible strip: character on the left wing, status on the right wing.
struct CompactBar: View {
    let snapshot: ConnectorSnapshot
    let mood: CharacterMood

    var body: some View {
        HStack {
            CharacterView(mood: mood, pixelSize: 2)
            Spacer()
            trailingIndicator
        }
    }

    @ViewBuilder private var trailingIndicator: some View {
        if !snapshot.pendingApprovals.isEmpty {
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
