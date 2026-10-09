import SwiftUI

/// Optional progressive-disclosure timer. State lives in AppModel, not a tab,
/// so moving between the menu bar, notch, and four tabs cannot restart it.
struct FocusTimerView: View {
    @ObservedObject var controller: FocusTimerController

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Focus timer")
                Spacer(minLength: 0)
                Text("Local only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Picker("Timer session", selection: Binding(
                get: { controller.state.mode },
                set: { controller.choose($0) }
            )) {
                Text("Focus").tag(FocusTimerMode.focus)
                Text("5m break").tag(FocusTimerMode.shortBreak)
                Text("15m break").tag(FocusTimerMode.longBreak)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .accessibilityIdentifier("companion.focus.mode")

            Text(FocusTimerState.clockLabel(controller.state.remaining(at: Date())))
                .font(.title2.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
                .accessibilityLabel("Time remaining")
                .accessibilityIdentifier("companion.focus.remaining")

            if controller.state.phase == .finished {
                Text("Session complete. Start again or choose a break.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Runs only while Pixel Companion is open. No completion notification.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button(controller.state.phase == .running ? "Pause" :
                       controller.state.phase == .paused ? "Resume" : "Start") {
                    controller.toggle()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("companion.focus.toggle")
                Button("Reset") { controller.reset() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("companion.focus.reset")
            }
        }
        .companionCard()
        .accessibilityIdentifier("companion.utility.focus")
    }
}
