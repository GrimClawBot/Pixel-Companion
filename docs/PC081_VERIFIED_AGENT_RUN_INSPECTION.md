# PC-081 — Agent → verified recent run inspection

## Purpose

Complete another segment of the whole-v1 Company → Agent → Task → Run
navigation **without pretending Paperclip supplied run logs or full history**.

The Agent Inspector's *Recent runs* section now provides a selectable
read-only detail for a source-reported run. A selected run is continually
re-resolved against the latest **live** `AgentSessionSnapshot.recentRuns`
feed by its exact nonempty run ID. Missing, duplicate or stale run IDs
cannot open a detail panel. Changing the selected agent resets the
drilldown via the SwiftUI agent-identity key. When a selected run falls
out of the bounded recent feed, the UI falls back to the run list.

The detail presents:
- The complete verified run ID, backend-reported state and optional
  provider/model, started/finished/updated times, and reported token counts.
- The linked *current task* only when
  `AgentRunSnapshot.issueID == TaskSnapshot.id` exactly and uniquely.
  A task's present-day assignee need not equal the historical run's agent.
  Matching titles, agent roles or current assignment are not proof.
- Explicit unavailable states for an absent/unverified task and for
  **redacted run logs that were not supplied**. Never interpolate the
  raw log output, hidden arguments, credentials or chat transcript.

Navigation is local and never calls a new endpoint or sends a Paperclip
action. The earlier task → run detail view stays intact (LOCKED-BUILT).
All expanded notch, compact notch, character, settings, public GitHub,
context and handoff previews and existing tabs are preserved.

## Tests

Native XCTest covers:
- live unique run IDs only; stale, nil, missing and duplicate IDs fail;
- exact structured run issue ID uniquely identifies a task even when
  the task now has a different assignee;
- a similar task title or a blank/duplicate issue ID never creates a
  false association.

Existing native Swift + Python, lint, build, secrets/config checks
must pass at this exact GitHub PR head before Mac preview installation.

## Owner Mac QA81

QA80 remains available as a rollback until QA81 succeeds. When
authorized to test the new build, quit QA80 with its own Quit control
and compile a new QA81 from a clean source checkout:

```bash
mkdir -p "$HOME/Developer" &&
git clone --depth 1 --branch pc-081/verified-agent-run-inspection \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA81" &&
bash "$HOME/Developer/Pixel-Companion-QA81/scripts/qa_preview_macos.sh" --qa-number 81
```

The audited owner-local script refuses existing QA81 paths/symlinks,
uses a private per-build Info.plist, signs/verifies the generated
bundle, validates marker `PCQAUpdateNumber=81`, and doesn't enable
real Login Items. It does not overwrite QA80 or publish a binary.

Confirm General shows **QA Update #81** and the correct version marker.
With live Paperclip available, select Agents → an agent → Recent runs
→ one run. Inspect source IDs, model/provider, provenance and task
link; use Recent runs to go back. Test invalid/stale/disconnected
source, agent-switch reset, long IDs/roles and 360pt/440pt layouts,
VoiceOver/keyboard and external display/menu bar fallback. No backend
writes, approvals, raw logs or new notifications.

If satisfied with QA81, older QA80 may be moved into recoverable
macOS Trash only after signed-app/process verification under the
owner's standing permission to retire older QA apps. Never empty
Trash or delete source, settings, or the canonical installed app.

## Review gates

This is a DRAFT stacked PR, **not** protected-main integration.
Native CI, Greptile technical review, independent human approval and
owner Mac acceptance are separate gates. No real outgoing chat,
session creation, private API access, notarization or public release.
