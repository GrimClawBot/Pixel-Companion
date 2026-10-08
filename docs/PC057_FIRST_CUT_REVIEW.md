# PC-057 — First safe integration cut: reviewed early Alpha

Snapshot: October 8, 2026. No merge to main or public distribution
has been performed, authorized, or scheduled.

## First proposed cut

Integration root PR #51:
- Source branch: integration/pixel-companion-readonly-alpha
- Target: main
- Exact inspected head SHA: 4fb64e19368a6af314c495dec840b79c59b268c8
- 58 commits; 70 changed files; about 5,745 additions and 293 deletions
- Independent temporary checkout passed full Mac native quality gate,
  including **192 Swift tests, zero failures**
- Tooling, config, branch/committed secret scans, strict SwiftLint,
  and warnings-as-errors build PASS
- Virtual merge with origin/main clean
- No source branch refs, provider config or main were modified

The first cut is already substantial. Review the Alpha as an independent
unit before later stacked features. Do not cherry-pick the 18 older PRs
separately; their heads are already Git ancestors of the current
cumulative integration candidate.

## Reproducible protection and approval check

From an authorized Pixel Companion checkout:

    python3 scripts/quality/protected_cut_audit.py \
      --pr 51 \
      --head integration/pixel-companion-readonly-alpha \
      --output /tmp/pixel-pc057-first-cut-gate.json

Exit 3: BLOCKED (expected). Exit 2: incomplete metadata (fail closed).
Exit 0: machine-readable conditions passed and a HUMAN can consider
authorization. The checker NEVER merges or approves. It cannot update
GitHub branch rules or refs, modify provider configs, publish, or
deploy an app. It matches GitHub's PR head with inspected Git commit,
checks CI and review decisions, and performs a virtual Git merge.
The virtual merge may create unreachable Git objects without moving
branch refs or the working tree. Reports contain no personal data.

## Current verified blockers

1. main currently has NO branch protection: GitHub protection endpoint
   returned 404, and repository ruleset list was empty.
2. PR #51 remains DRAFT with no APPROVED GitHub review.
   CodeRabbit was explicitly asked to review the Alpha and the latest
   candidate #125; a review request or COMMENTED response is NOT approval.
3. The first 58-commit cut needs named independent security review.
4. Actual spoken VoiceOver/full keyboard-only navigation and notarized
   public-distribution checks remain open.
5. Current protected-cut tool reports BLOCKED, with clean virtual merge
   but absent enforced approvals and required CI policy.

## Recommended main branch protection (owner decision required)

Under GitHub repository Settings > Branches or Rules > Rulesets:
- Require a pull request to update main
- Require at least one independent approving code review
- Dismiss outdated reviews after source changes
- Require successful native-checks from the current head
- Block force pushes and branch deletion
- Do not allow uncontrolled bypasses for administrators

Verify rules actually apply to main. The read-only gate currently
checks the legacy protection API for an enforced approving-review
count and CI contexts/checks. Active ruleset equivalence requires
separate validation and must not be assumed. PC-057 changes NO rule.

## Controlled integration sequence (not executed)

1. Owner explicitly approves branch protection; verify enforcement.
2. Review the entire PR #51 cut at its exact final source SHA, record
   a formal independent GitHub APPROVED decision and passing CI.
3. Repeat isolated QA and manually inspect private-data, app,
   connector, notification, security and accessibility boundaries.
4. Request a separate, explicit owner decision to merge that cut.
   Merge only the approved ancestry-preserving candidate, without
   immediately publishing a public app.
5. Review later stacked feature PRs in dependency order, then
   reconcile older PR records only after their desired commits are
   demonstrably contained in the approved integration target.

Disposition: BLOCKED. QA54 stays installed and running; there are no
changes to Paperclip, Codex, Claude, Sky notifier or main.
