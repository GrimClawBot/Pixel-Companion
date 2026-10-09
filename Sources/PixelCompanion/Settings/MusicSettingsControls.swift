import SwiftUI

/// Access is never requested in Settings; connecting happens only inside
/// the optional Music card via a separate explicit user action.
struct MusicSettingsControls: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Toggle("Enable Apple Music Now Playing", isOn: $model.musicWidgetEnabled)
            .accessibilityIdentifier("companion.settings.music-widget")
        if model.musicWidgetEnabled {
            Toggle("Show track and artist names", isOn: $model.musicShowTrackDetails)
                .accessibilityIdentifier("companion.settings.music-track-details")
            Text("Apple Music only. Connecting requires explicit macOS " +
                 "Automation permission. No playback controls, history or files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
