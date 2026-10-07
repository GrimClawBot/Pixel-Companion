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
        window.title = "Pixel Companion Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            connectorSection
            paperclipSection
            mockSection
            presentationSection
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    private var connectorSection: some View {
        Section("Connector") {
            Picker("Connector", selection: $model.connectorID) {
                ForEach(ConnectorRegistry.options) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            Text(selectedSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var paperclipSection: some View {
        if model.isPaperclipConnector {
            Section {
                TextField("Base URL", text: $model.paperclipBaseURL)
                    .textFieldStyle(.roundedBorder)
                if model.paperclipCompanies.isEmpty {
                    TextField("Company ID", text: $model.paperclipCompanyID)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Company", selection: $model.paperclipCompanyID) {
                        Text("Choose a company").tag("")
                        ForEach(model.paperclipCompanies) { company in
                            Text(company.name).tag(company.id)
                        }
                    }
                }
                HStack {
                    LabeledContent("Status", value: model.snapshot.connectionState.displayName)
                    Spacer()
                    Button("Refresh") { model.refreshConnector() }
                }
                if let error = model.snapshot.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Paperclip")
            } footer: {
                Text("Read-only. Pixel Companion sends GET requests only and stores no Paperclip credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mockSection: some View {
        Section {
            Picker("Connection", selection: $model.mockConnectionState) {
                ForEach(ConnectionState.allCases, id: \.self) { state in
                    Text(state.displayName).tag(state)
                }
            }
            Stepper(value: $model.mockStepInterval, in: SettingsStore.stepIntervalRange, step: 1) {
                Text("Next step every \(Int(model.mockStepInterval)) s")
            }
            Button("Restart script") { model.restartScript() }
        } header: {
            Text("Mock connector")
        } footer: {
            Text("Simulates the connection locally. Nothing outside this app is contacted or changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!model.isMockConnector)
    }

    private var presentationSection: some View {
        Section("Presentation") {
            Picker("Show in", selection: $model.presentation) {
                ForEach(PresentationPreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.radioGroup)
            LabeledContent("Now showing in", value: model.activeMode == .notch ? "Notch" : "Menu bar")
            if !model.notchAvailable {
                Text("No display with a notch is connected, so the menu bar is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedSummary: String {
        ConnectorRegistry.options.first { $0.id == model.connectorID }?.summary ?? ""
    }
}
