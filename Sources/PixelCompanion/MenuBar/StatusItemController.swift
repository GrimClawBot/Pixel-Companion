import AppKit
import Combine
import PixelCompanionCore
import SwiftUI

/// Menu-bar fallback: the mood symbol is the compact state, its tooltip the hover snapshot, and
/// a click opens the detail view in a popover.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var subscriptions: Set<AnyCancellable> = []

    init(model: AppModel, openSettings: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 440)
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView(model: model) { [weak self] in
            self?.popover.performClose(nil)
            openSettings()
        })

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))

        model.$mood
            .combineLatest(model.$snapshot, model.$feedFreshness)
            .sink { [weak self] mood, snapshot, freshness in
                self?.render(mood: mood, snapshot: snapshot, freshness: freshness)
            }
            .store(in: &subscriptions)
    }

    func remove() {
        subscriptions.removeAll()
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func render(
        mood: CharacterMood, snapshot: ConnectorSnapshot, freshness: FeedFreshness
    ) {
        guard let button = statusItem.button else { return }
        let label = "Pixel Companion: \(mood.title)"
        let image = NSImage(systemSymbolName: mood.symbolName, accessibilityDescription: label)
        image?.isTemplate = true
        button.image = image
        let activity = freshness.canPresentAsLive
            ? (snapshot.currentActivity?.title ?? snapshot.connectionState.displayName)
            : (freshness.warning ?? snapshot.connectionState.displayName)
        button.toolTip = "\(mood.title) · \(activity)"
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    var body: some View {
        DetailContent(
            snapshot: model.snapshot, mood: model.mood,
            openSettings: openSettings, feedFreshness: model.feedFreshness,
            lastSuccessfulSync: model.lastSuccessfulPaperclipSync,
            selectedTab: $model.selectedDetailTab
        )
            .padding(16)
            .frame(width: 360, height: 440, alignment: .top)
    }
}
