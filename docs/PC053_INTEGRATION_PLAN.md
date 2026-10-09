# PC-053 — Controlled integration preflight

Snapshot collected October 8, 2026 using the active GitHub account,
local Git ancestry and a read-only virtual merge check. No PR was
merged, retargeted, deleted, force-pushed or marked ready.

## How to regenerate the evidence

Run in the canonical Pixel Companion checkout:

    python3 scripts/quality/premerge_audit.py \
      --tip pc-052/release-review-folder-chain \
      --output /tmp/pixel-companion-premerge-audit.json

Exit code 3 means BLOCKED, not a script failure. Exit 2 means
incomplete metadata; exit 0 means only that the machine-readable
PR, check, and Git preflight passed, NOT that a human authorized merging.
The script can never merge, close, approve or mutate branch refs. It uses
the connected GitHub CLI for PR metadata and git merge-tree --write-tree
for a virtual merge; the latter may write unreachable Git objects but
never changes main, any branch ref or the current worktree. JSON output
contains PR numbers, branch names and review/check states, no private
provider config, agent event payloads or credentials.

## Verified result at this snapshot

- 50 open PRs, including 48 draft and two older non-draft (#14, #16).
- Five direct-to-main roots: #14, #16, #19, #21, and #51.
- 32 PRs form the current linear integration branch chain from #51
  through #117; ordered oldest to newest:

  #51, #53, #55, #57, #66, #67, #68, #70, #72, #74, #76,
  #77, #79, #81, #84, #85, #87, #89, #91, #93, #95, #97,
  #99, #101, #103, #105, #107, #109, #111, #113, #115, #117.

- Eighteen older open PR heads are not in that PR-base chain:
  #14, #16, #19, #21, #23, #25, #27, #29, #31, #33, #35,
  #37, #39, #41, #43, #45, #47 and #50.
- All 18 older heads ARE Git commit ancestors of the current
  integration tip. They introduce NO independent code delta.
  Keep their review and history, but do not apply/merge them a second
  time as unrelated patches. After a reviewed integration cut, reconcile
  their PR records by comparing actual merged commit ancestry.
- 50 PRs have no GitHub APPROVED review decision at this snapshot.
  All 50 had successful named CI checks; none was currently classified
  as conflicting by the GitHub PR metadata. CI alone is not approval.
- origin/main is an ancestor of the candidate. The virtual Git merge
  result was clean and generated a tree; main and the checkout did
  not change.

## Mandatory release gates (still OPEN)

1. Assign independent human/security reviewers and/or run an actual
   Greptile code review; do not mistake Greptile OSS enrollment for a
   passed verdict. The macOS shell used here has no Greptile CLI key
   and no GitHub token environment variable (the gh CLI is signed in).
2. Review sensitive command execution, provider hook fan-out, Python
   installer rollback, storage/auth/keychain, notification gating,
   file/event permissions, connectors and public/private separation.
3. Complete actual human VoiceOver/keyboard, macOS notch/non-notch,
   multi-display and live window/event acceptance. Sanitized renders
   pass, but System Events Accessibility was denied (-25211).
4. Verify release signing/notarization and that public standalone
   distribution contains no private Pixel HQ configuration or endpoints.
5. Review all 32 candidate stages, recording final reviewer decisions.
   Once reviewers explicitly approve a sequence, use small reviewed
   integration cuts instead of blindly merging all 50 open PRs.
6. Close/rebase redundant PR records ONLY after the final reviewed
   target contains the exact intended commits and the reviewer has
   authorized reconciliation.

Disposition: main merge remains blocked. This is a plan and a
read-only audit, not merge authorization; the installed QA52 app and
Codex/Claude/Paperclip runtime remain unchanged.
