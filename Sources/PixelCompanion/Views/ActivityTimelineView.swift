import PixelCompanionCore
import SwiftUI

/// Filters apply only to locally received event data, never to a Paperclip query.
enum ActivityTimelineScope: String, CaseIterable, Identifiable {
    case all
    case running
    case completed
    case failed
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All events"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .notes: return "Notes"
        }
    }

    func includes(_ event: ActivityEvent) -> Bool {
        switch self {
        case .all: return true
        case .running: return event.kind == .running
        case .completed: return event.kind == .completed
        case .failed: return event.kind == .failed
        case .notes: return event.kind == .note
        }
    }
}

struct ActivityTimelineSection: Identifiable {
    let id: String
    let label: String
    let events: [ActivityEvent]
}

enum ActivityTimelinePresentation {
    static func filtered(
        _ events: [ActivityEvent], query: String, scope: ActivityTimelineScope
    ) -> [ActivityEvent] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.enumerated()
            .filter { _, event in
                scope.includes(event) && (term.isEmpty ||
                    [event.title, event.detail]
                        .compactMap { $0 }
                        .contains { $0.localizedStandardContains(term) })
            }
            .sorted { lhs, rhs in
                if lhs.element.timestamp != rhs.element.timestamp {
                    return lhs.element.timestamp > rhs.element.timestamp
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func sections(
        _ events: [ActivityEvent], now: Date, calendar: Calendar
    ) -> [ActivityTimelineSection] {
        var output: [ActivityTimelineSection] = []
        var bucket: [ActivityEvent] = []
        var currentKey: String?
        var currentLabel = ""

        for event in events {
            let (key, label) = dateGroup(event.timestamp, now: now, calendar: calendar)
            if let existingKey = currentKey, key != existingKey {
                output.append(ActivityTimelineSection(
                    id: existingKey, label: currentLabel, events: bucket
                ))
                bucket = []
            }
            currentKey = key
            currentLabel = label
            bucket.append(event)
        }
        if let currentKey {
            output.append(ActivityTimelineSection(
                id: currentKey, label: currentLabel, events: bucket
            ))
        }
        return output
    }

    static func emptyMessage(
        total: Int, query: String, scope: ActivityTimelineScope
    ) -> String {
        if total == 0 { return "No activity recorded by this connector." }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No activity matches that search. Try another keyword."
        }
        if scope != .all { return "No \(scope.label.lowercased()) events in this history." }
        return "No activity available."
    }

    static func hasValidTime(_ date: Date) -> Bool {
        date != .distantPast
    }

    private static func dateGroup(
        _ date: Date, now: Date, calendar: Calendar
    ) -> (String, String) {
        guard hasValidTime(date) else { return ("unknown", "Date not reported") }
        let key = "day-\(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate)"
        if calendar.isDate(date, inSameDayAs: now) { return (key, "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return (key, "Yesterday")
        }
        return (key, date.formatted(date: .abbreviated, time: .omitted))
    }
}

/// A bounded, per-event view; time is only presented when supplied by the connector.
struct ActivityTimelineRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.kind.rawValue.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                    Spacer(minLength: 4)
                    if ActivityTimelinePresentation.hasValidTime(event.timestamp) {
                        Text(event.timestamp, style: .relative)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Time not reported")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(event.title)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .companionCard()
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch event.kind {
        case .note: return "info.circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .note: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

struct ActivityTimelineView: View {
    let events: [ActivityEvent]
    let isLive: Bool
    @State private var query = ""
    @State private var scope: ActivityTimelineScope = .all

    private var visible: [ActivityEvent] {
        ActivityTimelinePresentation.filtered(events, query: query, scope: scope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: isLive ? "Recent activity" : "Cached history")
                Spacer(minLength: 0)
                Text("\(visible.count) / \(events.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TextField("Search activity…", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search activity")
                .accessibilityIdentifier("companion.activity.search")
            Picker("Event type", selection: $scope) {
                ForEach(ActivityTimelineScope.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .accessibilityIdentifier("companion.activity.kind")
            if visible.isEmpty {
                Placeholder(text: ActivityTimelinePresentation.emptyMessage(
                    total: events.count, query: query, scope: scope
                ))
            }
            ForEach(ActivityTimelinePresentation.sections(
                visible, now: .now, calendar: .current
            )) { section in
                SectionTitle(text: section.label)
                ForEach(section.events) { event in
                    ActivityTimelineRow(event: event)
                }
            }
        }
    }
}
