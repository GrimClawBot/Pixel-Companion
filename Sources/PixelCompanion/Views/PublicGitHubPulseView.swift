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

    /// GitHub branch names are untrusted presentation text. In particular,
    /// bidi control characters can visually reorder a source branch.
    static func branchLabel(_ run: GitHubPublicRun) -> String? {
        guard let name = run.headBranch else { return nil }
        let spaced = name.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let bidi = CharacterSet(charactersIn:
            "\u{061C}\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}" +
            "\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}"
        )
        let sanitized = spaced.unicodeScalars
            .filter { !bidi.contains($0) && !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    static func runAccessibilityLabel(_ run: GitHubPublicRun) -> String {
        var parts = [
            "Open public GitHub workflow " + workflowLabel(run),
            "Status " + status(run)
        ]
        if let branch = branchLabel(run) {
            parts.append("Branch " + branch)
        }
        return parts.joined(separator: ", ")
    }

    static func pullAccessibilityLabel(_ pull: GitHubPublicPull) -> String {
        "Open public GitHub PR #\(pull.number), " + pull.title
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

    private var sourceRepository: PublicGitHubRepository? {
        PublicGitHubRepository(state.repository)
    }

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
                        if let destination = sourceRepository?.publicRunPage(id: run.id) {
                            Link(destination: destination) {
                                runRow(run, isLink: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(GitHubPublicPresentation.runAccessibilityLabel(run))
                            .accessibilityHint("Opens the public workflow on github.com in a browser")
                            .accessibilityIdentifier("companion.github.public-run-link")
                        } else {
                            runRow(run, isLink: false)
                        }
                    }
                    Text("Open pull requests · \(state.openPulls.count) shown")
                        .font(.caption.weight(.semibold))
                    ForEach(state.openPulls) { pull in
                        if let destination = sourceRepository?.publicPullPage(number: pull.number) {
                            Link(destination: destination) {
                                pullRow(pull, isLink: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(GitHubPublicPresentation.pullAccessibilityLabel(pull))
                            .accessibilityHint("Opens the public pull request on github.com in a browser")
                            .accessibilityIdentifier("companion.github.public-pr-link")
                        } else {
                            pullRow(pull, isLink: false)
                        }
                    }
                    if let sourceRepository {
                        Link("View public repository", destination: sourceRepository.publicRepositoryPage())
                            .font(.caption2.weight(.medium))
                            .accessibilityIdentifier("companion.github.public-repo-link")
                    }
                }
                Text("Public repositories only · Browser links open on request. No private GitHub access.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .companionCard()
            .accessibilityIdentifier("companion.github.public-ci")
        }
    }

    private func runRow(_ run: GitHubPublicRun, isLink: Bool) -> some View {
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
                if let branch = GitHubPublicPresentation.branchLabel(run) {
                    Text("Branch · " + branch)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if isLink {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pullRow(_ pull: GitHubPublicPull, isLink: Bool) -> some View {
        HStack(spacing: 7) {
            Text("#\(pull.number) · \(pull.title)")
                .font(.caption2)
                .lineLimit(2)
            Spacer(minLength: 0)
            if isLink {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
