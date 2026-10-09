# PC-072 — Compact reporting-branch disclosure

## UI

PC-071 introduced the new source-verified Reporting tab view. PC-072
improves its compact Mac presentation without removing List, By Role,
manager navigation, or any accepted agent and task views.

- A separate chevron alongside each **verified manager with direct reports**
  collapses/expands that manager's visible subordinate branch.
- **Collapse all** hides all source-verified subordinate rows, keeping roots
  visible. **Expand all** restores the full available reporting forest.
- Direct-report counts include **only immediate verified children**; never
  imply a complete company headcount, title-based organization, or access rights.
- A nested manager remains collapsed if a previously collapsed ancestor is
  reopened, until the owner expands that nested branch.
- Missing, filtered-out, self-referential, or cyclic manager IDs are never
  treated as valid parent links. Such rows remain independently visible.
- Collapsed state lives in SwiftUI memory only; a changed visible reporting
  set, manager relationship, filter or feed freshness resets disclosure state.
  No settings or telemetry are persisted or transmitted.
- A manager row still has an independent **Inspect [agent]** action.
  Collapsing is a separate button with VoiceOver label and direct-report count.
  Deep indentation is capped at four levels for narrow screens.

## Acceptance

The pure hierarchy tests cover exact verified direct-report counts, preservation
of other roots when collapsing a manager, nested collapse/reopen, invalid
manager/cyclic links, and empty source data. They do not replace real Mac QA.

Native human QA on 360pt/440pt widths and VoiceOver should check:
1. Switch List → By role → Reporting with no functionality lost.
2. Collapse an intermediate manager; unrelated sibling/root rows remain
   navigable. Expand and check the exact source-reported descendants.
3. Collapse all, then expand one root; nested managers remain collapsed
   until deliberately expanded. Expand all restores every verified row.
4. Search for a leaf or use Active filter: do not invent a missing manager;
   clear stale disclosure state after a changed source/filter.
5. Verify **Inspect agent**, **Reports to manager**, back navigation and
   scroll/focus with long names, dynamic text sizes and Reduce Motion.
6. Disconnect/reconnect and simulate changed `reportsTo` relationships;
   stale agent telemetry must not be presented as live reporting.
7. Confirm no endpoint writes, file/config changes or new permissions.

## Deferred product work

Paperclip's `reportsTo` is a manager agent ID, not a department ID. Verified
backend departments, secure private approvals, redacted logs, task→PR provenance,
Atlas chat/session authorization and all public release steps are separately
tracked. These disclosure interactions do not grant or alter permissions.

This PR is deliberately draft and stacked on PC-071. GitHub Actions native
CI, Greptile technical review, independent GitHub human approval and real
Mac interaction acceptance are separate gates. Installed QA61, PC-065
Launch at Login real-system acceptance #148, protected main and Paperclip
production must remain unchanged.
