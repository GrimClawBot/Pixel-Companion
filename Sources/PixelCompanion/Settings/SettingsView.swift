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
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var loginItem = LaunchAtLoginController()
    @State private var paperclipBaseURLDraft: String
    @State private var githubPublicRepositoryDraft: String

    init(model: AppModel) {
        self.model = model
        _paperclipBaseURLDraft = State(initialValue: model.paperclipBaseURL)
        _githubPublicRepositoryDraft = State(initialValue: model.githubPublicRepository)
    }

    var body: some View {
        Form {
            connectorSection
            paperclipSection
            githubPublicSection
            mockSection
            presentationSection
            startupSection
            notificationSection
            aboutSection
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
                TextField("Base URL", text: $paperclipBaseURLDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.applyPaperclipBaseURL(paperclipBaseURLDraft) }
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
                    Button("Refresh") { model.applyPaperclipBaseURL(paperclipBaseURLDraft) }
                }
                if let lastSync = model.lastSuccessfulPaperclipSync {
                    LabeledContent("Last successful sync") {
                        Text(lastSync, style: .relative)
                    }
                } else {
                    LabeledContent("Last successful sync", value: "Not yet")
                }
                if let warning = model.feedFreshness.warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
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

    private var githubPublicSection: some View {
        Section("GitHub · public repositories only") {
            TextField("owner/repo (optional)", text: $githubPublicRepositoryDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.applyGitHubPublicRepository(githubPublicRepositoryDraft) }
                .accessibilityIdentifier("companion.github.repository")
            Button("Apply public repository") {
                model.applyGitHubPublicRepository(githubPublicRepositoryDraft)
            }
            .disabled(githubPublicRepositoryDraft == model.githubPublicRepository)
            Text("Optional. Reads public workflow runs and open PRs using GitHub GET requests. " +
                 "No login, private repository access, credentials or GitHub actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = model.publicGitHubState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
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

    private var startupSection: some View {
        Section("Startup") {
            Toggle("Launch at Login", isOn: Binding(
                get: { loginItem.enabled },
                set: { loginItem.setEnabled($0) }
            ))
            .disabled(!loginItem.canChange)
            .accessibilityIdentifier("companion.settings.launch-at-login")
            Text(loginItem.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if loginItem.canChange {
                Button("Refresh login status") { loginItem.refresh() }
                    .controlSize(.small)
            }
        }
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

    private var notificationSection: some View {
        Section {
            Toggle("System notifications", isOn: $model.notificationsEnabled)
            Text(model.notificationStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.notificationPermissionNeedsRequest {
                Button("Grant permission…") { model.requestNotificationPermission() }
            }
            Button("Send test notification") {
                Task { await model.sendTestNotification() }
            }
            .disabled(!model.canSendTestNotification)
            if CompanionBuildInfo.qaUpdate != nil {
                Button("Simulate new approval (local QA)") { model.simulateQAEvent(.newApproval) }
                    .disabled(!model.canSimulateQAEvent)
                Button("Simulate run completed (local QA)") { model.simulateQAEvent(.runCompleted) }
                    .disabled(!model.canSimulateQAEvent)
                Button("Simulate run failed (local QA)") { model.simulateQAEvent(.runFailed) }
                    .disabled(!model.canSimulateQAEvent)
                Text("QA-only simulated events. No data is sent to Paperclip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let status = model.notificationTestStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(
                "Off by default. New Paperclip approvals and agent run completions/failures only. "
                    + "No task or identity details in banners; existing events are not replayed."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: CompanionBuildInfo.version)
            if let qaUpdate = CompanionBuildInfo.qaUpdate {
                LabeledContent("Update", value: qaUpdate)
            }
        }
    }

    private var selectedSummary: String {
        ConnectorRegistry.options.first { $0.id == model.connectorID }?.summary ?? ""
    }
}
