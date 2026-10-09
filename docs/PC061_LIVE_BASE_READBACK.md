# PC-061 — Re-read protected main immediately before audit readiness

Greptile follow-up review run 1251ba48-ed06-4932-8a6b-3a7a319fcb49
on PC-059 identified a remaining P1 time-of-check/time-of-use gap in
the read-only integration review audit.

The previous audit fetched the live GitHub base SHA near the start,
then made slower review, branch, check-run, ancestry and virtual-merge
requests. If main advanced during those operations, the tool could
still announce REVIEW_READY for the old base and stale virtual merge.

## Resolution

The audit now resolves local origin/main once to an immutable
40-character commit SHA and uses that exact value for BOTH git
merge-base --is-ancestor and git merge-tree --write-tree. Moving
references are no longer consulted during those local checks.

After all PR metadata, review, check-run, protection and Git checks
finish, the audit re-reads the live GitHub main branch SHA. It
explicitly refuses readiness when this final read differs from the
pinned base, the first live GitHub base, or the PR baseRefOid.
It also fails closed if the final API call is unavailable, malformed
or returns no SHA. An absent final read produces exit code 2;
a changed base produces exit code 3. Either case cannot announce
REVIEW_READY or authorize a merge.

The JSON review record includes the final-base-stable flag, final
lookup availability and any blockers. The read-only audit does not
update main, force-push, merge, publish, alter PR approval or
modify Paperclip, Codex or Claude settings. A clean result remains
only an input to a separate explicit human merge decision. GitHub
branch protection revalidates the branch when an actual merge is
requested, since no client-side audit can guarantee future immutability.

## Reproducible tests

- An unchanged initial and final base with all other controlled
  conditions fulfilled remains *review ready for human decision only*.
- An initial valid SHA followed by a different final SHA blocks.
- Missing/malformed final GitHub branch metadata blocks.
- Matching final SHA never rescues an invalid initial base comparison.
- End-to-end mocked GitHub and Git calls prove that a green PR with
  human approval is still blocked if main moves during the audit.
- End-to-end tests prove the Git ancestry and virtual merge use
  the immutable pinned commit, not origin/main, and final lookup
  failure returns an incomplete status rather than readiness.

Run:

    python3 -m unittest scripts.quality.tests.test_protected_cut_audit -q
    python3 scripts/quality/protected_cut_audit.py \
      --pr 51 --head integration/pixel-companion-readonly-alpha \
      --output /tmp/pixel-pc061-preflight.json

The real PR #51 is still DRAFT with no independent GitHub APPROVED
review. Greptile provides technical findings, not human approval.
AlphaGrimStalker is not requested, per owner's explicit preference.

PC-061 is audit tooling and documentation only: no new QA app
version is justified; verified QA56 stays installed and running.
The separate PC-060 Greptile review must be assessed against
its exact reviewed SHA before declaring PC-060 formally reviewed.
