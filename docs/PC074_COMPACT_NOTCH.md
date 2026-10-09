# PC-074 — Compact-notch readability (Mac Alpha)

## Purpose

The owner's real QA72 screenshots reveal a very small pixel character and
mostly empty black space directly below the camera housing. This patch
changes **only** the collapsed/compact notch strip and its shared character
rendering size, preserving the already accepted hover snapshot, detail panel,
menu-bar fallback, settings, controls and original artwork.

- Compact strip extends **32 points** below the notch instead of 24,
  staying strictly within the physical camera housing's horizontal width.
  The animated pixel sprite uses 2.6-point blocks instead of 2-point blocks.
- The compact strip, and **only** that strip, displays a concise status label
  next to the character. Long mood names truncate and scale down instead of
  stretching into neighboring menu-bar items.
- Real Paperclip freshness overrides cached moods: **Connecting**,
  **Updates delayed**, and **Disconnected** replace a stale Working/Testing
  label and use source-appropriate SF Symbols. Live/standalone mock uses the
  already verified character mood.
- Existing live pending-approval pill remains unchanged and never shows
  cached approvals when the Paperclip feed is stale.
- An accessible status label is available in compact mode; the character's
  duplicate accessibility announcement is suppressed only in this mode.
  No new background poll, permission, telemetry or API write is introduced.

## Mac visual/interaction acceptance

1. On the MacBook notch, inspect Idle, Working, Waiting, and offline/stale
   compact strips at 100% and enlarged Display scaling. Confirm sprite
   stays below the camera housing, label remains readable and menu-bar
   items on both sides remain clickable/uncovered.
2. Hover to snapshot, click to detail, dismiss back to compact; verify
   no regression to sizes, hover targets, expansion or outside click.
3. Test long mood labels like **Infrastructure alert**, priority of live
   approval badges, and connector outages; stale should never say Working.
4. Check Reduce Motion/VoiceOver behavior; no duplicate mood reading in
   compact mode, status and pending approvals remain accessible.
5. Test external display and explicit Menu bar mode, which must continue
   to work with no notch and must not use the new compact strip.
6. Confirm source version/build markers and no OS Login Items mutation.

This is a DRAFT, stacked source-only change on PC-073. Its native CI is not
real-device UI acceptance. Existing QA72 installation and QA61 rollback are
preserved; neither app is silently updated. Greptile technical review,
independent human GitHub approval and owner-authorized protected integration
remain separate gates.
