# PC-052 — Pixel Companion release-readiness audit

Audit date: October 8, 2026. Production candidate before this audit:
QA51, commit d5c5428c3733e96a62a0493658cf296012d41880.
PC-052 applies additional hook-directory hardening, not a public release.

## GitHub/repository inventory verified on the Mac

- **47 open pull requests.** The majority are draft, layered changes.
  Two older PRs (#14 and #16) are already non-draft.
- The latest source is 92 commits ahead of main and modifies 178 files,
  totaling approximately 17,187 additions and 421 deletions.
- Recent stacked pull requests (#115, #113, #109, #101 and #85) and the
  root integration PR #51 had no formal submitted GitHub review.
  Native-checks was SUCCESS on the latest PR. This is not a full
  independent security or functional review.
- No Greptile API or GitHub token variables were set in the connected
  Mac terminal used for CLI review. Greptile account enrollment does
  not demonstrate that an automated verdict was completed.
  Optional Gitleaks CLI was not installed; the native quality gate
  still runs its own secret and changed-commit scanners.

## PR hierarchy and consolidation policy

- Staging integration root PR #51 targets main.
- The later linear chain includes PRs #53, #55, #57, #66, #67, #68,
  #70, #72, #74, #76, #77, #79, #81, #84, #85, #87, #89, #91,
  #93, #95, #97, #99, #101, #103, #105, #107, #109, #111,
  #113 and #115. Each later PR is based on its previous feature branch.
- Earlier draft/undraft PRs targeting main, including #14, #16, #19,
  and #21, may overlap with ancestor commits in the integration chain.
  Do not merge them all as independent patches without reviewing
  their exact commit ancestry.
- Do not squash/force-push reviewed history, close open PRs or merge
  into main merely to reduce the open PR count. Review by source and
  trust boundary, record findings, then merge in approved dependency
  order after all applicable gates are met.

## Accepted technical evidence

- Codex CLI 0.161.0 genuine minimal read-only turn delivered a
  mode-0600, schema-valid agent-turn-complete event to the private
  folder; Claude Code did the same for SessionEnd. These event
  markers are not cryptographic proof of the process that wrote them.
- Existing SkyComputerUseClient Codex notify is preserved via
  fan-out; old Codex CLI 0.154.0 remains available for rollback.
  No global Codex model setting was changed.
- QA51 ad-hoc signed build, source SHA, active process and removal
  of QA50 were verified; 415 Swift tests plus tooling tests passed.
- Real SwiftUI views were rendered with sanitized fixtures at menu-bar
  360pt and notch-detail 440pt widths in Light and Dark appearances.
  The bug that indefinitely showed stale markers as recent was fixed.
- Paperclip's configured local health endpoint returned HTTP 200
  without modifying production Paperclip settings.

## Outstanding release blockers — do not merge or publish

1. A named independent code/security review is needed across the full
   17k-line cumulative change, particularly the provider hook
   installer and original Codex command fan-out, folder/link storage,
   auth/credentials/egress, optional Pixel HQ connectivity, process
   presence semantics, CI and release provenance.
2. Obtain the Greptile code review verdict or assign and document
   appropriately scoped human review. The current repository gate
   requires explicit human review for sensitive execution/config/CI
   surfaces even after automated tests pass.
3. Actual macOS VoiceOver/keyboard and live-window interactions are
   **unverified**: System Events returned Accessibility error -25211.
   Do not silently change Mac privacy controls or treat offscreen
   snapshots as interactive end-to-end acceptance.
4. Confirm genuine local-provider events displayed on the running
   app screen, not just valid marker files and sanitized test renders.
5. Validate Focus/notifications, reduced motion, narrow Settings,
   multi-display, sleep/wake, notch/non-notch and installer recovery.
6. Verify public standalone core boundaries and externally kept
   Pixel-specific credentials/config. Release signing is local
   ad-hoc only; public notarization/distribution has not happened.

## Hardening completed by PC-052

The managed optional auto-connect checks that ALL three
app-controlled components are existing, current-user-owned,
owner-private, non-symlink folders: the Pixel Companion directory,
Agent Events directory and provider folder. Regression tests now
reject symlinked parent directories and publicly readable parents,
while allowing the original private folders. The change does not
alter providers, network egress, credentials or Paperclip production.

Decision: continue review in stacked drafts, no merge into main,
no public release, and no claims of VoiceOver acceptance.
