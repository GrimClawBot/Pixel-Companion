import Foundation
import SwiftUI
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

@MainActor
final class CompanionSharedNavigationTests: XCTestCase {
    func testNotchAndMenuBarBindingsShareTabSelection() {
        let suite = "PixelCompanionNavTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = AppModel(settings: SettingsStore(defaults: defaults))
        XCTAssertEqual(model.selectedDetailTab, .overview)

        // Notch and menu-bar hosts build their own bindings to this same model.
        let notch = Binding<CompanionDetailTab>(
            get: { model.selectedDetailTab },
            set: { model.selectedDetailTab = $0 }
        )
        let menuBar = Binding<CompanionDetailTab>(
            get: { model.selectedDetailTab },
            set: { model.selectedDetailTab = $0 }
        )

        notch.wrappedValue = .usage
        XCTAssertEqual(menuBar.wrappedValue, .usage)

        // The selection survives switching presentation and connector states.
        model.updatePresentation(mode: .menuBar, notchAvailable: false)
        model.start()
        model.connectorID = .disabled
        XCTAssertEqual(menuBar.wrappedValue, .usage)

        menuBar.wrappedValue = .activity
        model.updatePresentation(mode: .notch, notchAvailable: true)
        XCTAssertEqual(notch.wrappedValue, .activity)

        // A new app model has a clean transient tab; no disk persistence.
        let nextModel = AppModel(settings: SettingsStore(defaults: defaults))
        XCTAssertEqual(nextModel.selectedDetailTab, .overview)
    }

    func testOverviewShortcutsRouteToVisibleExistingTabs() {
        XCTAssertEqual(CompanionOverviewShortcut.allCases.count, 3)
        XCTAssertEqual(CompanionOverviewShortcut.agents.target, .agents)
        XCTAssertEqual(CompanionOverviewShortcut.active.target, .agents)
        XCTAssertEqual(CompanionOverviewShortcut.approvals.target, .activity)
        for shortcut in CompanionOverviewShortcut.allCases {
            XCTAssertTrue(CompanionDetailTab.allCases.contains(shortcut.target))
        }
    }
}
