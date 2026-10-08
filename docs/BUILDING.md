# Building and running

Requirements: macOS 14 (Sonoma) or later, Xcode 16 or later (Swift 5.10+). There are no
third-party dependencies and no accounts or keys to configure.

## Command line

```sh
swift build                      # debug build
swift run PixelCompanion         # build and launch the app
swift test                       # core + native macOS app tests
scripts/quality/check.sh --base origin/main   # the full PC-000 gate (also: make quality)
```

`swift run` keeps the app attached to the terminal; quit it from the companion's detail view
(**Quit**) or with Ctrl-C. The app has no Dock icon: it lives in the notch or the menu bar.

## Xcode

1. `open Package.swift` (or File ▸ Open… and pick the repository folder).
2. Select the **PixelCompanion** scheme and the **My Mac** destination.
3. Run with ⌘R; run the unit tests with ⌘U.

Xcode creates the schemes from `Package.swift`; there is no `.xcodeproj` to keep in sync, so
`QUALITY_XCODE_SCHEME` is not needed by the gate.

## First launch

- On a MacBook with a notch the companion appears around the notch. Hover it for a snapshot;
  click it for the detail view; press Esc or click elsewhere to collapse it.
- Without a notch (older Macs, lid closed on an external display) a symbol appears in the menu
  bar. Click it for the detail view; hover it for a tooltip.
- **Settings…** in the detail view switches the connector, simulates mock connection states,
  configures an optional read-only Paperclip base URL/company, changes the mock step interval, and
  picks the notch, the menu bar, or automatic placement.

### Paperclip

Choose **Paperclip** in Settings, enter a reachable `http://` or `https://` base URL, then use
**Refresh** to discover companies. Select a company when more than one is available. Pixel Companion
stores only the base URL and company ID in `UserDefaults`; it does not store Paperclip credentials.
The connector sends GET requests only.

Settings are stored in the app's `UserDefaults` domain. To start fresh:

```sh
defaults delete PixelCompanion   # domain name of an unbundled SwiftPM executable
```

## Linux

`PixelCompanionCore` uses Foundation only and contains all of the logic, but the package also
contains the AppKit app, so building it needs macOS.

## Agent usage dashboard (PC-009, local QA)

In the expanded notch or menu-bar detail view, Agent usage · latest
reported run retains the existing sessions list and adds per-agent
model/provider, input/cached/output token counts (for the selected reported
run), and monthly agent spend/budget from Paperclip agent telemetry
(spentMonthlyCents, budgetMonthlyCents). These billing amounts are not
per-run estimates. Unknown metrics are shown as unavailable, not zero.

Context percentage and 80%/90% warnings are shown only if the runtime
explicitly returns valid usageJson.contextUsedTokens and
usageJson.contextWindowTokens for that run. No context limit is inferred
from a model name, the cumulative input tokens, or the number of messages.
When Paperclip doesn't return these fields, the UI says Context usage
unavailable. The dashboard requires no extra HTTP endpoints, credentials,
or writes. The standalone mock connector works with no Paperclip instance.

## Tabbed companion detail (PC-011, local QA)

The expanded **detail** view in both the notched panel and the menu-bar
popover is divided into **Overview**, **Agents**, **Usage**, and **Activity**.

- Overview retains the connection header, active counts, featured activity,
  the immediate approvals preview and the existing company usage summary.
- Agents retains the agent/session list with state, model/provider, run and
  session details.
- Usage retains company and per-agent spend/budget, run tokens, context
  availability, accurate warnings and the All/Active agent filter.
- Activity retains the complete pending approvals list, event history
  and available messages.
- Settings and Quit stay in the fixed footer; Settings remains a separate window.

The header and tabs do not scroll out of view. The notch's compact and hover
behavior is unchanged, but its **detail panel** no longer treats tapping tab
buttons as an outside click or notch expansion gesture. The app remains
read-only and does not request new privileges or back-end access.

For macOS visual QA, verify each of the four tabs in the **notch detail** and
the **360-point menu-bar popover**. Test clicking/keyboard navigation, long
agent names, 0/4/many agents, connection loss, approvals, notifications,
and switching back and forth without dismissing the detail surface.

## Shared detail navigation (PC-012)

The selected tab lives in the in-memory AppModel, not in UserDefaults.
Notch details and the menu-bar fallback bind to the same selected tab. Hover
collapse, opening the menu bar, and changing presentation mode preserve the
selection during the current app session. Relaunching starts at Overview.

The Overview Agents, Active, and Approvals summary tiles are
keyboard-accessible navigation buttons to their respective tabs. The separate
View usage details link opens Usage. No shortcut acts on Paperclip or
changes its permissions.

## Native panel visual polish (PC-013)

Agents and per-agent Usage entries share a lightweight rounded-card treatment
with uniform padding and subtle borders, removing redundant list dividers.
The full Agents row moves its relative update time below the title and metadata
to protect narrow layouts, and all run states have readable status chips.
The compact snapshot still uses the slim unboxed row.

The selected tab has a subtle accent underline. Tab switches and Overview
shortcuts use a short ease-in-out animation unless macOS **Reduce Motion** is
enabled, in which case the selection switches without animation. No persistent
theme settings, backend writes, network endpoints, or additional dependencies
were added. Compare the notch (440pt) and menu-bar popover (360pt) manually for
clipping and long text before releasing any public binary.

## Detail keyboard navigation (PC-014)

While the notch detail panel or menu-bar popover has keyboard focus:
Command-1 opens Overview, Command-2 Agents, Command-3 Usage, and
Command-4 Activity. Left/right arrows move through tabs when the tab strip
has focus, stopping at the first/last tab. Each tab has an accessibility
label, selected trait/value and a high-contrast underline. Content scroll
resets to the top on tab change; a long Usage list must not leave the user
partway down Activity. Selection remains shared in memory across the two
surfaces. macOS Reduce Motion continues to disable navigation animations.

Mac manual QA is needed for tab keyboard focus and actual VoiceOver
announcement in both the notch and menu-bar popover; unit tests verify
shortcut/destination logic but cannot replace interactive verification.

## Agent inspector (PC-015, local QA only)

In **Agents**, click an existing agent card to inspect the most recently
reported state, task, provider/model, shortened session/run identifier,
timestamps, run tokens, monthly agent budget/spend, and optional context
usage. A **Back to all agents** button returns to the list. The detail view
uses the current connector snapshot by *stable agent ID* on every refresh,
rather than retaining stale per-run data. It automatically returns to the
list when that agent disappears or the feed is unavailable. Missing model,
runtime and context metrics are visibly unavailable; no amounts are guessed.
All cards remain read-only: selection never starts, stops, approves or edits
an agent.

Mac visual QA: test mouse/keyboard selection on notch and menu-bar, use Back,
inspect different agents, change tabs while selected, test connector failure
and recovery, long task/model names, and both known/unknown telemetry fields.
No public binary distribution is allowed yet.

## Searchable Agents directory (PC-016, local QA)

The Agents tab now has a local Search field and **All / Active** segmented
filter. Search checks the already-reported name, title, task, provider, model
and status, case/diacritic-insensitively. The search is purely in memory and
never sends typed text to Paperclip or another provider. The existing
inspect-an-agent and All agents back behavior is preserved; filters apply to
the directory list, not the selected inspector's live session identity.

The UI reports the filtered count and differentiates no agents, no active
agents, no search matches, and disconnected/stale data. Disconnected or stale
feed cannot expose cached agents as current. No server requests, permissions
or public API changes were added. Manual QA should check keyboard typing and
clear, All/Active filtering, inspector/back, active run updates, and 360-point
menu-bar vs 440-point notch behavior before merging.

## Read-only Activity timeline (PC-017)

Activity keeps all existing read-only pending approvals and messages, but shows
recent events in a chronological timeline. Search matches the received event
title/detail locally and a compact event-kind menu filters All, Running,
Completed, Failed and Notes. Results are newest-first, with stable order for
identical timestamps. Day headings distinguish Today, Yesterday, dated
earlier history and Date not reported; missing timestamps are never displayed
as current. During a stale/disconnected feed, events are visibly labeled as
**Cached history**, not live results. An empty feed and a search with no matches
have distinct messages.

The source event contract does **not** include guaranteed agent identity for
all events. The timeline therefore does not claim accurate per-agent event
history based on matching text alone. No extra Paperclip endpoints, writes,
data persistence, privileges or third-party dependencies are added.
Human macOS QA must test Search and filter together, changing dates, cached
history, approvals/messages, and both 440pt notch and 360pt menu bar.

## Verified recent runs in each Agent inspector (PC-018)

Paperclip telemetry already fetches up to 40 recent heartbeat runs and
50 live runs, with each run's structured agentId. The agent inspector now
shows a maximum of five of these already-retrieved runs, sorted newest-first
and deduplicated by run ID. It does not send new API requests or write to
Paperclip. A run's task label comes from its structured issueId joined to
the current issue snapshot (which may have a newer title than at run time).
Per-run provider/model and tokens come only from each run's usageJson, with
invalid/negative values discarded. Missing fields, timestamps, and metrics
are clearly unavailable. Runs that cannot be confirmed active are not shown
as running.

This is bounded recent history, not a complete historical audit trail.
The existing latest session and monthly budget remain separate from per-run
data. The public AgentSessionSnapshot gained the backward-compatible
recentRuns default-empty field and the new AgentRunSnapshot type, making
PC-018 a public API change that needs independent human/security review
under PC-000 even when all automated checks pass.

Real Mac QA: several agents, both notch/menu-bar layouts, missing runs/usage,
newest-first order, stale/disconnected feeds, status transitions, and selecting
another agent must not show somebody else's runs. Public release remains blocked.

## Verified live session monitor (PC-019)

The Agent inspector includes a read-only **Session monitor** card driven only
by the current reported run state and actual timestamps. Running shows an
indeterminate activity indicator, **not a completion percentage**. Queued,
completed, failed, cancelled, idle and unconfirmed statuses never show a
misleading spinner. The spinner is suppressed when macOS Reduce Motion is
enabled. Reported start, last reported update, and finish are labeled
explicitly. Duration is computed only for a terminal run with valid start/end
ordering, not for idle or unconfirmed states. Values are never guessed.

The context meter shows only explicitly reported valid used/window tokens and
reuses the existing utilization/warning policy (80%/90%). Input/output run
totals do not stand in for the window. Within the inspector the preexisting
monthly-spend/running-tokens card remains, but its context portion is shown
in the monitor instead of duplicated; the full per-agent Usage tab is intact.

This feature adds no public models, endpoints, credentials or server mutations
and does not change the existing connector polling schedule. Mac interaction
QA is still required for running/idle/stale states, Reduce Motion and
VoiceOver at the 440pt notch and 360pt menu-bar widths. No public binary
release is authorized.
