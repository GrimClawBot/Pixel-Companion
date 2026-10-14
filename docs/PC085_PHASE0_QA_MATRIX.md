# PC-085 Phase 0 — screen/component inventory and human Mac QA matrix

Baseline: source SHA `96adbd5`. Everything below was inventoried from source on Linux. **Nothing here was compiled,
rendered or VoiceOver-tested.** Each row requires human execution on macOS 14+ (preferably on a notch MacBook).

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
synthetic `ConnectorSnapshot.noConnector` across widths 360/440, light/dark, standard/accessibility text size,
and freshness states notApplicable/connecting/current/stale/unavailable × moods idle/working/waitingForApproval/
error/offline. By default it only asserts that a non-empty PNG renders. PNGs are written only when
`PIXEL_DESIGN_REFERENCE_DIR` is set. It does not touch the real desktop, settings, connectors or the network.

**Not compiled on the Linux worker** (no Swift toolchain). First step on the Mac:
`PIXEL_DESIGN_REFERENCE_DIR=/tmp/pc085-ref swift test --filter DesignReferenceRenderTests`.

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

Out of scope for this matrix: PC-065 real Launch at Login acceptance, provider hooks, release governance.
