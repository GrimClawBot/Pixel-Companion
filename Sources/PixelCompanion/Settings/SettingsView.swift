import AppKit
import PixelCompanionCore
import SwiftUI

/// Hosts `SettingsView` in an ordinary window; reused across openings.
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // An accessory app is not frontmost by default; bring the window forward.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = CompanionBuildInfo.settingsTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 700, height: 490)
        window.setContentSize(NSSize(width: 850, height: 610))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// Stable native Settings destinations; selection is a local navigation choice,
/// never a connector mutation or a permission request.
enum CompanionSettingsPane: String, CaseIterable, Identifiable {
    case general
    case connections
    case utilities
    case notifications

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .connections: return "Connections"
        case .utilities: return "Utilities"
        case .notifications: return "Notifications"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .connections: return "point.3.connected.trianglepath.dotted"
        case .utilities: return "square.grid.2x2"
        case .notifications: return "bell"
        }
    }

    var detail: String {
        switch self {
        case .general: return "Appearance, startup, and power preferences"
        case .connections: return "Choose which sources Pixel Companion can read"
        case .utilities: return "Optional tools that work independently of Pixel HQ"
        case .notifications: return "Control when the Mac can alert you"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject var loginItem = LaunchAtLoginController()
    @State private var selectedPane: CompanionSettingsPane = .general
    @State var paperclipBaseURLDraft: String
    @State var githubPublicRepositoryDraft: String

    init(model: AppModel) {
        self.model = model
        _paperclipBaseURLDraft = State(initialValue: model.paperclipBaseURL)
        _githubPublicRepositoryDraft = State(initialValue: model.githubPublicRepository)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPane) {
                Section("Preferences") {
                    ForEach(CompanionSettingsPane.allCases) { pane in
                        Label(pane.title, systemImage: pane.symbol)
                            .tag(pane)
                            .accessibilityIdentifier("companion.settings.pane." + pane.rawValue)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 195, max: 225)
            .accessibilityIdentifier("companion.settings.sidebar")
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: selectedPane.symbol)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)
                        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedPane.title)
                            .font(.title2.weight(.semibold))
                        Text(selectedPane.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Form {
                    switch selectedPane {
                    case .general:
                        presentationSection
                        startupSection
                        energySection
                        aboutSection
                    case .connections:
                        connectorSection
                        paperclipSection
                        githubPublicSection
                        if model.isMockConnector {
                            mockSection
                        }
                    case .utilities:
                        focusTimerSection
                    case .notifications:
                        notificationSection
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .windowBackgroundColor))
                .accessibilityIdentifier("companion.settings.details")
            }
            .navigationTitle(selectedPane.title)
        }
        .frame(minWidth: 700, minHeight: 490)
        .accessibilityIdentifier("companion.settings.window")
    }

}
