import SwiftUI

enum GitHubPublicPresentation {
    static func workflowLabel(_ run: GitHubPublicRun) -> String {
        let title = run.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed workflow"
    }

    static func status(_ run: GitHubPublicRun) -> String {
        if run.status != "completed" { return run.status.replacingOccurrences(of: "_", with: " ").capitalized }
        guard let conclusion = run.conclusion else { return "Completed · result not reported" }
        return conclusion.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func symbol(_ run: GitHubPublicRun) -> String {
        if run.status != "completed" { return "clock" }
        switch run.conclusion {
        case "success": return "checkmark.circle"
        case "failure", "timed_out": return "xmark.circle"
        default: return "questionmark.circle"
        }
    }
}

struct PublicGitHubPulseView: View {
    let state: GitHubPublicState

    var body: some View {
        if state.phase != .off {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    SectionTitle(text: "GitHub · public CI")
                    Spacer(minLength: 0)
                    Text("Read-only")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(state.repository)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)

                switch state.phase {
                case .off: EmptyView()
                case .loading:
                    Text("Checking public GitHub status…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .unavailable:
                    Text(state.errorMessage ?? "Public repository status unavailable")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                case .ready:
                    if let fetched = state.fetchedAt {
                        HStack {
                            Text("Last verified")
                            Text(fetched, style: .relative)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Text("Recent workflow runs")
                        .font(.caption.weight(.semibold))
                    if state.runs.isEmpty {
                        Text("No public workflow runs reported")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(state.runs) { run in
                        HStack(spacing: 7) {
                            Image(systemName: GitHubPublicPresentation.symbol(run))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(GitHubPublicPresentation.workflowLabel(run))
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(GitHubPublicPresentation.status(run))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("Open pull requests · \(state.openPulls.count) shown")
                        .font(.caption.weight(.semibold))
                    ForEach(state.openPulls) { pull in
                        Text("#\(pull.number) · \(pull.title)")
                            .font(.caption2)
                            .lineLimit(2)
                    }
                }
                Text("Public repositories only · No private GitHub access")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .companionCard()
            .accessibilityIdentifier("companion.github.public-ci")
        }
    }
}
