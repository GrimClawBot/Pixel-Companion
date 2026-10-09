import SwiftUI

/// Independent from Paperclip activity; never promotes local events to
/// company agent status or misrepresents a marker as task completion.
struct LocalAgentActivityTimelineView: View {
    @ObservedObject var timeline: LocalAgentActivityTimeline
    @State private var filter: LocalAgentActivityFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Local AI activity")
                Spacer(minLength: 0)
                Text("Codex + Claude Code")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Picker("Local activity source", selection: $filter) {
                ForEach(LocalAgentActivityFilter.allCases, id: \.self) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .accessibilityIdentifier("companion.activity.local-filter")

            TimelineView(.periodic(from: .now, by: 30)) { context in
                let visible = timeline.visible(filter: filter, at: context.date)
                if visible.isEmpty {
                    Text("No recent hook events observed in this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visible.prefix(8)) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(event.source.label)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 74, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.label)
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(
                                        LocalAgentEventPresentation.timelineTimingLabel(
                                            event.timestamp, at: context.date
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                Text(event.timestamp, style: .relative)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if visible.count > 8 {
                            Text("\(visible.count - 8) earlier events retained in memory")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Best-effort latest-marker updates · not a complete agent history. " +
                 "Nothing is recorded before enabling the hooks.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .companionCard()
        .accessibilityIdentifier("companion.activity.local-timeline")
    }
}
