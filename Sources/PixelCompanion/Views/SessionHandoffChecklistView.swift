import PixelCompanionCore
import SwiftUI

/// A read-only review checklist; it never drafts a transferable prompt or
/// creates a backend session, copies to the clipboard or persists private data.
struct SessionHandoffChecklistView: View {
    let session: AgentSessionSnapshot
    let assignedTasks: [TaskSnapshot]
    let isLive: Bool
    @State private var isExpanded = false

    private var evidence: SessionHandoffEvidence? {
        SessionHandoffEvidence.prepare(
            session: session, assignedTasks: assignedTasks, isLive: isLive
        )
    }

    var body: some View {
        Group {
            if let evidence {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Observed source facts · not a generated handoff")
                            .font(.caption.weight(.medium))
                        LabeledContent("Agent", value: evidence.agentName)
                        LabeledContent("Agent ID", value: evidence.agentID)
                        if let sessionID = evidence.sessionID {
                            LabeledContent("Session ID", value: sessionID)
                        }
                        if let runID = evidence.runID {
                            LabeledContent("Run ID", value: runID)
                        }
                        LabeledContent("Run state", value: evidence.runState.rawValue.capitalized)
                        if let model = evidence.model {
                            LabeledContent("Model", value: model)
                        }
                        if let provider = evidence.provider {
                            LabeledContent("Provider", value: provider)
                        }
                        contextSection(evidence)
                        Text("Currently assigned tasks · verified IDs only")
                            .font(.caption.weight(.semibold))
                        if evidence.assignedTasks.isEmpty {
                            Text("No source-assigned tasks in the current bounded feed.")
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        } else {
                            ForEach(evidence.assignedTasks, id: \.sourceID) { task in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.displayTitle)
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("Reported state · " + task.status)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if evidence.evidenceIsBounded {
                            Text("Showing only five verified assignments from the current feed.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("Information still required before any real handoff")
                            .font(.caption.weight(.semibold))
                        ForEach(SessionHandoffEvidence.missingForHandoff, id: \.self) { field in
                            Label(field + " · not supplied", systemImage: "circle.dashed")
                                .font(.caption2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Review only · No chat, handoff, copy, upload or approval is performed.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Handoff readiness · review only", systemImage: "doc.text.magnifyingglass")
                        .font(.callout.weight(.semibold))
                }
                .accessibilityIdentifier("companion.session.handoff-checklist")
            } else {
                Text("Handoff evidence unavailable until agent telemetry is live.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: isLive) { _, live in
            if !live { isExpanded = false }
        }
        .onChange(of: session.agentID) { _, _ in
            isExpanded = false
        }
        .onChange(of: session.sessionID) { _, _ in
            isExpanded = false
        }
        .onChange(of: session.runID) { _, _ in
            isExpanded = false
        }
    }

    @ViewBuilder private func contextSection(_ evidence: SessionHandoffEvidence) -> some View {
        if let fraction = evidence.contextHealth.fraction {
            Text("Provider-reported context · \(Int(fraction * 100))% of window")
                .font(.caption2.monospacedDigit())
            Text(evidence.contextHealth.recommendation.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Context occupancy not reported by this runtime.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
