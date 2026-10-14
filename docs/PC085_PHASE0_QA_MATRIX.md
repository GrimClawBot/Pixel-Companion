# PC-085 Phase 0 — screen/component inventory and human Mac QA matrix

Baseline: source SHA `96adbd5`. The inventory below was taken from source on Linux. The fixture harness (§3) has been
compiled and run once on the owner's Mac (see the evidence log). **No surface has been VoiceOver-tested or visually
accepted, and no screen outside the fixture's `CompactBar` + `SummaryHeader` has been rendered.** Each matrix row
still requires human execution on macOS 14+ (preferably on a notch MacBook).

## 1. Surfaces and screens

| Surface | Entry view | File |
|---|---|---|
| Notch compact / expanded | `NotchRootView`, `CompactBar` | `Notch/NotchViews.swift` |
| Glance header | `SummaryHeader`, `SnapshotContent` | `Views/CompanionViews.swift` |
| Detail tabs | `CompanionTabBar`, `DetailContent` (overview/agents/usage/activity) | `Views/CompanionTabBar.swift`, `Views/DetailContent.swift` |
| Menu-bar fallback | `MenuBarPopoverView` | `MenuBar/StatusItemController.swift` |
| Agents | `AgentsDirectoryView`, `AgentInspectorView`, `AgentRunHistoryView`, `AgentSessionMonitorView`, `LocalAgentSessionsView`, `ClaudeHookView`, `CodexTurnView`, `CodexProcessView` | `Views/` |
| Activity | `ActivityTimelineView`, `LocalAgentActivityTimelineView`, `LiveActivityDigestView` | `Views/` |
| Usage | `AgentUsageCard`, `UsageBar` | `Views/AgentUsageDashboard.swift` |
| Tasks | `CompanyTasksView`, `CompanyTaskEvidenceView`, `TaskRunEvidenceView` | `Views/` |
| Operations | `LiveOperationsPulseView`, `OperationalAttentionView`, `LocalAgentAttentionView`, `ContextHealthSummaryView`, `SessionHandoffChecklistView`, `PublicGitHubPulseView`, `LocalInfrastructureView` | `Views/` |
| Utilities | Focus, Battery, Brightness, Volume, Download, Music, Calendar, Clipboard, File shelf views | `Views/` |
| Settings | `SettingsView` sections general/connections/utilities/notifications + controls | `Settings/` |
| Shared | `CompanionCardStyle`, `CompanionMotion`, `SectionTitle`, `Placeholder`, `ApprovalCountBadge`, `CharacterView` | `Views/` |

## 2. Accessibility identifier contract (must not be renamed)

`companion.notch.statusButton`, `companion.tabs`, `companion.tab.{overview,agents,usage,activity}`,
`companion.detail.content`, `companion.feed.warning`, `companion.health.refresh`, `companion.live-activities`,
`companion.operations.{pulse,attention,approvals}`, `companion.overview.{usage,local-attention}`,
`companion.attention.open-activity`, `companion.context.{health,keep-working}`, `companion.session.handoff-checklist`,
`companion.activity.{kind,search,local-filter,local-timeline}`,
`companion.agents.{search,filter,group-layout,local-feed,claude-hook,codex-process,codex-turn}`,
`companion.agent.{inspector,back,run-back,run-history,inspect-run,verified-run-detail,session-monitor,assigned-tasks,assigned-task-select,reported-manager,reporting-row,reporting.all,reporting.toggle,feed.warning}`,
`companion.tasks.{company,search}`, `companion.task.{select,back,evidence,linked-run,run-detail,run.back,current-assignee,agent-shortcut}`,
`companion.usage.filter`, `companion.github.{repository,public-ci,public-pr-link,public-repo-link,public-run-link}`,
`companion.infrastructure.local`,
`companion.utility.{focus,battery,display-brightness,output-volume,download-progress,music,calendar,clipboard,file-shelf}`,
`companion.focus.{toggle,reset,mode,remaining}`, `companion.clipboard.{save,clear,notice}`, `companion.file-shelf.{add,clear}`,
`companion.music.connect`, `companion.calendar.grant`, `companion.setup.managed-auto-connect`,
`companion.settings.{window,sidebar,details,launch-at-login,cancel-pending-login,conserve-energy,…}` (full list:
`grep -rhoE 'accessibilityIdentifier\("[^"]+"\)' Sources | sort -u`, 110+ IDs at 96adbd5).

Phase 1+ PRs must diff this list and show **no removals or renames**.

## 3. Fixture reference harness

`Tests/PixelCompanionAppTests/DesignReferenceRenderTests.swift` renders `SummaryHeader` and `CompactBar` with
synthetic `ConnectorSnapshot.noConnector` across widths 360/440, light/dark, standard (`.large`) / `.accessibility3`
text size, and freshness states notApplicable/connecting/current/stale/unavailable × moods idle/working/
waitingForApproval/error/offline (5 of the 13 `CharacterMood` cases). PNGs are written only when
`PIXEL_DESIGN_REFERENCE_DIR` is set. It does not touch the real desktop, settings, connectors or the network.

What it asserts (none of it compares pixels, so it does not depend on the OS version):
- `testReferenceMatrixCoversEveryFreshnessStateWithUniqueNames`: all 5 `FeedFreshness` states are listed (an
  exhaustive `switch` stops it compiling if a case is added), and the matrix yields 200 unique file names.
- `testReferenceLayoutsRenderWithoutWallClockText`: each of the 200 configurations renders a non-empty PNG.

**The PNGs are reference fixtures for human review, not approved golden images.** No visual regression baseline
exists. One should be adopted only after owner visual acceptance and a decision on how to pin OS/fonts.

**Time-dependent text is excluded on purpose.** The harness passes `lastSuccessfulSync: nil`, so the header hides the
"Last synced" row. Production renders that row with `Text(date, style: .relative)`, which depends on the wall clock.
The first Mac run used `MockScript.referenceDate` (2026-01-01) and the PNGs showed an age of about 9 months that would
change on every run. Coverage for the "Last synced" label is now the manual matrix row 18 below. Production code is
unchanged.

**Known limitation: standard vs accessibility text.** On the first Mac run, all 100 std/ax3 pairs were
pixel-identical (see the evidence log). Setting `.dynamicTypeSize` on this macOS hosting path did not change the
rendered output: `CompactBar` uses a fixed 12 pt font, and the semantic fonts in `SummaryHeader` did not scale
either. The ax3 configurations stay in the matrix to show they render. They do **not** show large-text support.
Fixing that is production work and belongs to owner-gated Phase 1/2 (see the acceptance criteria below).

Run on the Mac: `PIXEL_DESIGN_REFERENCE_DIR=/tmp/pc085-ref swift test --filter DesignReferenceRenderTests`.
The Linux worker has no Swift toolchain, so the Phase 0B edits to this file have not been compiled.

## 4. Human Mac QA matrix

Configurations: **A** light/standard text, **B** dark/standard, **C** dark + largest text, **D** Increase Contrast +
Reduce Transparency, **E** Reduce Motion, **F** VoiceOver on. Mark each cell Pass/Fail/N/A, with a screenshot path.

| # | Check | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|
| 1 | Compact notch: plate pure black, sprite crisp, fits physical notch | | | | | | |
| 2 | Compact status never shows "live/healthy" when stale/unavailable/connecting | | | | | | |
| 3 | `companion.notch.statusButton` announced as one actionable status | | | | | | |
| 4 | Expanded glance: mood, freshness, last sync, approvals visible in that order | | | | | | |
| 5 | Tabs ⌘1–⌘4 and ←/→; selected state announced | | | | | | |
| 6 | Overview hierarchy: attention → now → health → utilities | | | | | | |
| 7 | Agents directory / inspector / run history / back navigation | | | | | | |
| 8 | Activity search + filters; empty state is neutral | | | | | | |
| 9 | Usage cards: numbers monospaced, no truncation at 360 | | | | | | |
| 10 | Menu-bar fallback (no-notch display) matches notch detail | | | | | | |
| 11 | Settings sidebar sections reachable; all toggles labelled; no key reset | | | | | | |
| 12 | Connector off by default; standalone app looks complete | | | | | | |
| 13 | Error/stale/empty states each show text + symbol, not color only | | | | | | |
| 14 | Reduce Motion: no tab/notch animation; character holds a frame, still visible | | | | | | |
| 15 | No flashing > 3 Hz; Conserve Energy honoured | | | | | | |
| 16 | Utilities (focus, clipboard, file shelf, music, calendar) unchanged behaviour | | | | | | |
| 17 | Existing installed QA86 build untouched | | | | | | |
| 18 | "Last synced" relative age is correct, updates and is announced (sync now / 5 min ago / stale) | | | | | | |
| 19 | Compact status and glance text grow with System Settings text size (expected **Fail** until Phase 1/2) | | | | | | |

Out of scope for this matrix: PC-065 real Launch at Login acceptance, provider hooks, release governance.

## Evidence log

| Date | Environment | Check | Result |
|---|---|---|---|
| 2026-10-13 22:52 EDT | Owner Mac, separate QA worktree (patch of `9d24492` as `c2d73df`), Xcode 26.6 / Swift 6.3.3 | `PIXEL_DESIGN_REFERENCE_DIR=… swift test --jobs 4 --filter DesignReferenceRenderTests` | PASS: 1 test, 0 failures, 200 PNG references generated (= 2 widths × 2 schemes × 2 text sizes × 5 freshness × 5 moods) |

| 2026-10-14 | Owner Mac QA (ChatGPT-assisted) hash review of the 200 PNGs above | SHA comparison of the outputs | 112 unique, 88 duplicates. **All 100 std-vs-ax3 pairs pixel-identical.** Header showed the relative "Last synced" age of `MockScript.referenceDate` (~9 months 13 days), so output depends on the wall clock |
| 2026-10-14 | Linux worker, Phase 0B | Fixture now passes `lastSuccessfulSync: nil` and adds name/coverage assertions; docs corrected | **Not compiled. Awaiting Mac revalidation** |

Still open: Mac re-run of the Phase 0B harness (expect 2 tests to pass, 200 PNGs, no "Last synced" row), visual
inspection of the PNGs, a VoiceOver pass, and every row of the matrix above.

## 5. Phase 1 acceptance criteria from Phase 0 evidence

Phase 1+ needs owner approval and is not authorised by this document.
1. Compact status and glance text use semantic or `@ScaledMetric` sizes, so at `.accessibility3` the std/ax3
   fixture pairs **differ** (hash-distinct) for every width/scheme/freshness/mood, with no clipping at 360 pt.
2. A test-only clock or formatter seam lets the "Last synced" label render deterministically in the fixture without
   changing what users see.
3. Before any PNG becomes a golden baseline, the owner signs off on it visually and the macOS/Xcode version is pinned.
4. Matrix rows 3, 18 and 19 pass under VoiceOver (column F) and largest text (column C).
5. The accessibility identifier list in §2 shows no removals or renames.
