# PC-058 — Required CI identity verification and fail-closed merge audit

The integration PR gate previously considered any set of successful named
CI checks sufficient, while only requiring that main branch protection
had at least one named required CI check. That is insufficient: a green
unrelated check (for example, a CodeRabbit bot check) can never prove that
the required native-checks workflow passed on the same PR candidate.

The corrected gate compares each exact required GitHub check context to
the actual check names in the PR's statusCheckRollup. Every required
context must appear exactly once with conclusion SUCCESS. Any
missing, repeated, failed, skipped, neutral or pending required check
fails closed. Every other named check is also required to be successful.

The gate also requires the existing protected-main policy to be enforced
as expected: at least one required independent review, stale approvals
dismissed, latest-push approval required, admins enforced, required CI
checks strict/up-to-date, and force-pushes/deletion disabled. Missing
or null protection components cannot be treated as approval.

Regression tests cover missing native-checks with only unrelated green
checks, multiple required contexts, skipped/neutral/pending/failed jobs,
duplicate named checks, invalid review counts, and protection bypass.
Run from the canonical checkout:

    python3 -m unittest scripts.quality.tests.test_protected_cut_audit -q
    python3 scripts/quality/protected_cut_audit.py \
      --pr 51 --head integration/pixel-companion-readonly-alpha

The real first-cut result remains BLOCKED because PR #51 is still
DRAFT and has no GitHub APPROVED review, despite correct main
protection and passing native CI. Reviewing an AI-generated report
is not a substitute for independent approval.

Greptile reviews of root PR #51 and PC-057 were started on the user's
request; the original runs target their frozen committed SHA and do
not automatically review later security fixes. Their eventual findings
need to be addressed against the applicable current branch HEAD.
Per user direction, no review is requested from AlphaGrimStalker until
specifically asked. Their collaborator access is left unchanged.

This tooling and documentation change does not merge, publish, create
GitHub approval, modify main, change provider/Paperclip configurations,
or alter the running local QA54 app.
