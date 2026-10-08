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

## Greptile independent code audit of the previous gate

The completed Greptile review run f411bc11-0bb0-48ba-9a91-aee95b92e8a0
reviewed PC-057 at commit 12f0693. It reported THREE P1 findings:
- green unrelated CI checks could hide missing native-checks;
- a stale origin/main ref could look mergeable against the old base;
- APPROVED alone could hide a bot, self-review, or approval on an old SHA.

This subsequent PC-058 patch specifically remedies all three in code:
- exact required CI name/unique successful conclusion;
- GitHub PR baseRefOid == live remote main SHA == local origin/main SHA;
- GitHub REST review records must contain at least the policy-required
  count of distinct independent, non-bot User approvals on exact head SHA,
  with current state APPROVED and GitHub reviewDecision APPROVED.

A later Greptile run is needed against the final PC-058 commit before
calling the audit findings closed by independent review. The live
first-cut remains BLOCKED until a human reviewer is requested and
approves. No such request is currently open at user direction.

The separate Greptile Alpha run 6e704bf0-f146-4c56-b364-21af817f7611
reviewed the historical PR #51 root, *not* the latest app. It raised
7 findings requiring current-code triage; two historically relevant
issues (redirect privacy and initial eight-session snapshot limits)
were already addressed by the latest approved QA work, but that does
not imply the entire Alpha candidate passes independent review.
