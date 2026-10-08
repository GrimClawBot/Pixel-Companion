import AppKit
import PixelCompanionCore
import SwiftUI

/// Native forms separated from the sidebar/navigation state.
extension SettingsView {
    var connectorSection: some View {
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

    @ViewBuilder var paperclipSection: some View {
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

    var githubPublicSection: some View {
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

    var mockSection: some View {
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

    var startupSection: some View {
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

    var presentationSection: some View {
        Section("Presentation") {
            Picker("Show in", selection: $model.presentation) {
                ForEach(PresentationPreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            LabeledContent("Now showing in", value: model.activeMode == .notch ? "Notch" : "Menu bar")
            if !model.notchAvailable {
                Text("No display with a notch is connected, so the menu bar is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var energySection: some View {
        Section("Energy") {
            Toggle("Conserve energy in Low Power Mode", isOn: $model.conserveEnergy)
                .accessibilityIdentifier("companion.settings.conserve-energy")
            Text("When macOS Low Power Mode is on, Paperclip checks slow from " +
                 "5 seconds to 20 seconds. Mock mode and GitHub refresh are unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var notificationSection: some View {
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

    var selectedSummary: String {
        ConnectorRegistry.options.first { $0.id == model.connectorID }?.summary ?? ""
    }
    @ViewBuilder var focusTimerSection: some View {
        Section {
            Toggle("Focus timer", isOn: $model.focusTimerEnabled)
                .accessibilityIdentifier("companion.settings.focus-timer")
            Toggle("Downloads", isOn: $model.downloadHUDEnabled)
                .accessibilityIdentifier("companion.settings.download-hud")
            Toggle("File shelf", isOn: $model.fileShelfEnabled)
                .accessibilityIdentifier("companion.settings.file-shelf")
            Toggle("Clipboard (manual capture)", isOn: $model.clipboardHistoryEnabled)
                .accessibilityIdentifier("companion.settings.clipboard-history")
        } header: {
            Text("Productivity")
        } footer: {
            Text("Focus is local; Downloads needs a provider. File shelf and " +
                 "Clipboard keep only user-chosen RAM state until disabled or quit.")
        }

        Section {
            Toggle("Battery & Power", isOn: $model.batteryHUDEnabled)
                .accessibilityIdentifier("companion.settings.battery-hud")
            Toggle("Output volume", isOn: $model.outputVolumeHUDEnabled)
                .accessibilityIdentifier("companion.settings.output-volume-hud")
            Toggle("Display brightness", isOn: $model.displayBrightnessHUDEnabled)
                .accessibilityIdentifier("companion.settings.display-brightness-hud")
        } header: {
            Text("Mac status")
        } footer: {
            Text("Read-only macOS values, when reported. No device history or controls.")
        }

        Section {
            MusicSettingsControls(model: model)
            Toggle("Next Calendar event", isOn: $model.calendarWidgetEnabled)
                .accessibilityIdentifier("companion.settings.calendar-widget")
            if model.calendarWidgetEnabled {
                Toggle("Show event titles", isOn: $model.calendarShowTitles)
                    .accessibilityIdentifier("companion.settings.calendar-show-titles")
                Text("Calendar permission is requested only when you select Grant " +
                     "access in the Overview widget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Personal")
        } footer: {
            Text("Off by default. Music and Calendar permissions are separate, explicit actions.")
        }
    }

    var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: CompanionBuildInfo.version)
            if let qaUpdate = CompanionBuildInfo.qaUpdate {
                LabeledContent("Update", value: qaUpdate)
            }
        }
    }

}
