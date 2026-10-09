import SwiftUI

/// The default presentation omits sensitive titles; users may enable titles
/// separately under Settings after granting Calendar read access.
struct CalendarNextEventView: View {
    @ObservedObject var monitor: CalendarNextEventMonitor
    let showTitles: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Next calendar event")
                Spacer(minLength: 0)
                Text("Local only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if monitor.access == .authorized {
                if let event = monitor.nextEvent {
                    Text(CalendarEventPresentation.displayTitle(
                        for: event, showTitles: showTitles
                    ))
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                    if event.isAllDay {
                        Text("All-day · " + event.start.formatted(
                            .dateTime.weekday(.wide).month(.abbreviated).day()
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(event.start, format: .dateTime.weekday(.wide).hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No upcoming events reported in the next 7 days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(monitor.access.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if monitor.access == .notRequested {
                    Button("Grant Calendar access…") {
                        Task { await monitor.requestAccess() }
                    }
                    .disabled(monitor.requestingAccess)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("companion.calendar.grant")
                }
            }
        }
        .companionCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.utility.calendar")
    }
}
