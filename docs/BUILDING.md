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

## Standalone macOS app bundle (PC-006)

The local packaging command builds a true `.app`, with a stable identifier, original generated
app icon, an accessory/menu-bar app plist, and an ad-hoc signature. No credentials are required:

```sh
scripts/package_macos.sh --release
open "dist/Pixel Companion.app"
```

Output: `dist/Pixel Companion.app` (ignored by Git). Relative `--output` paths resolve
from the caller's working directory, not the repository root. The script validates the signature,
stages the app on the destination filesystem, and preserves the previous default app if the
replacement fails. It refuses to overwrite existing custom destinations and rejects concurrent
packaging for the same output using a short, hashed sibling lock directory. If packaging is interrupted by a
forced termination, verify that no packaging process remains before manually removing a stale
lock. If the script reports RECOVERY REQUIRED, preserve the named Previous.app backup for
manual inspection/recovery; do not delete its stage directory. No app is published or notarized.
A macOS permission prompt should only appear when a feature explicitly requests it; the current
read-only features do not request notification permission.

For external distribution, a maintainer may supply a **Developer ID Application** signing
identity already installed in the local Keychain:

```sh
scripts/package_macos.sh --release --sign-identity "Developer ID Application: YOUR TEAM"
```

The local Developer ID signing option deliberately uses `--timestamp=none` so this
packaging script makes no network calls. A separately approved public-release procedure must
re-sign with an Apple secure timestamp and complete notarization.

**Existing settings do not automatically transfer** from the unbundled `swift run` executable
to the packaged app. The earlier executable commonly used the `PixelCompanion` UserDefaults
domain, while this bundle uses `io.github.grimclawbot.PixelCompanion`. After first launching
the installed app, reselect your connector and presentation settings and re-enter your optional
Paperclip base URL and company selection locally. This migration is manual by design; never
commit private connection settings to the public repository.

This alone is **not** a public release. A maintainer must review the signing inputs, notarize
with Apple's notary service, staple the ticket, verify Gatekeeper acceptance, and explicitly
approve any GitHub Release upload. Never commit signing keys, passwords or private profiles.

For real macOS QA: record the commit SHA, OS version, machine/notch availability, install path,
bundle identifier, codesign verification, launch/quit, menu bar/notch behavior, sleep/wake, and
permission prompts. Check notification allow/deny and delivery only after the PC-005 feature is
included in a reviewed bundled build. A successful SwiftPM test or app launch alone is not
evidence that system notifications work.

## Linux

`PixelCompanionCore` uses Foundation only and contains all of the logic, but the package also
contains the AppKit app, so building it needs macOS.

## macOS notifications (PC-005)

System notifications are **off by default**. In Settings, enable them deliberately and
approve the macOS permission prompt. If macOS has denied notifications, change permission in
System Settings instead. Disable the toggle to stop future delivery.

Only **new** Paperclip approval requests and observed agent run transitions from queued/running
to completed/failed generate notifications. Notices use generic text; they do not contain task
names, approval contents, agent names, session IDs, endpoints, logs or secrets. The app never
acts on requests or runs on your behalf. It only watches while Pixel Companion is running.

macOS Notification Center requires a properly installed app bundle with a stable bundle ID.
The development-only \`swift run PixelCompanion\` executable is not an app bundle and therefore
disables notification delivery safely. The notch, menu bar, Paperclip connector and other app
features still work in development mode. A distributable, signed \`.app\` bundle is a separate
release requirement; do not treat command-line tests as proof of system banner delivery.

Manual macOS QA for a bundled build: check permission allow/deny, enabling after connecting,
existing approvals not triggering, one new approval producing one notice, run completion/failure,
repeated polls not producing duplicates, changing companies/reconnecting not replaying existing
events, and disabling notifications. Verify the Notification Center content contains no private
data. Do not change Paperclip production to manufacture test events.

### Notification smoke test (PC-005)

With a locally packaged .app open, select Settings → Notifications and explicitly enable
system notifications. Grant the macOS permission prompt if one appears. After the status reads
"Enabled for new Paperclip events", click **Send test notification** to request a harmless
local banner: **Pixel Companion test — This is a local test notification.** No Paperclip
instance, credentials or network connection is required. If macOS permission is denied,
the button stays disabled. The app never fires the test automatically on launch or enable.

Check Notification Center if the banner is not immediately visible (Focus modes may suppress
banners). Record whether the alert appears; a successful build alone does not verify display.

### Simulated Paperclip notification checks (numbered QA bundles only)

A numbered QA bundle (identified by the optional \`PCQAUpdateNumber\` Info.plist
value) displays **Simulate new approval**, **Simulate run completed**, and
**Simulate run failed** in Settings → Notifications. These controls require
notification opt-in and macOS permission. Each uses a separate in-memory
\`CompanionNoticeDetector\` with synthetic events and requests a generic macOS
banner through the normal notification center adapter; it does not issue HTTP
requests, change Paperclip, or alter the live event baseline. Production bundles
without the QA update metadata hide and disable these controls.

The simulator validates local event detection and delivery only. It cannot
substitute for separately observing a genuine new Paperclip approval/run event.

## Feed freshness (PC-008 local development)

For the read-only Paperclip connector, the app stores **only in memory** the local
wall-clock time of the last successful *core* API poll. It does not equate a
refresh attempt, partial telemetry response, or cached agent row with a new
successful sync. The notch, menu-bar detail view and Settings show when data is
delayed or unavailable; active rows and pending approval counts are suppressed
when the feed is stale or disconnected. A fresh successful poll restores them.

With the default five-second Paperclip interval, the feed is stale after
20 seconds without a successful core refresh. The mock/disabled connectors are
unchanged. A previous sync timestamp is cleared when switching to a new
connector instance or company; it never persists across app launches. This
does not infer whether any agent is actually online or running; it only
reflects freshness of the data fetch.

No access tokens, Paperclip writes, or public distribution are involved.

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

## Live Operations pulse (PC-020)

Overview adds a compact read-only pulse for the latest confirmed reported
run states: Running, Queued and **Failed latest run**. It shows three counts
and up to two agents per category, preserving connector order. Clicking an
agent opens its existing live inspector under Agents, with the existing
stable-agent-ID and fresh-feed guards intact. No progress percentage,
pending-approval ownership or unreported state is inferred. Approval counts
are **company-wide**, with a separate shortcut to Activity instead of
pretending they belong to specific agents.

With a disconnected or stale feed, the pulse displays **unavailable** and
never presents cached counts, agents or approvals as live. Idle, completed,
cancelled and unconfirmed agents never inflate the running/queued/failed
counters. The app's four tabs, keyboard shortcuts, usage, recent runs,
session monitor and separate notifications remain unchanged. No new endpoint,
permission, persistent state or Paperclip mutation was introduced.
Human QA: inspect counts in both notch and menu-bar widths, tap each agent
shortcut, verify Back, approvals shortcut, empty state, stale feed/recovery,
and keyboard/VoiceOver access before accepting the UI.

## Operational attention digest (PC-021, local QA only)

Overview now includes an **Attention needed** panel. It derives read-only,
stable-per-agent/category diagnostic rows from **current live** agent snapshots:
the *latest reported* run failed, agent monthly spending is at least
80%/90%/100% of its *reported* monthly budget, or context-window occupancy is
at least 80%/90% using both explicitly reported token counts. Invalid or
missing budget/context measurements never become warnings; old failed history
does not imply a present failed run. The view sorts critical signals first,
preserves source order within severity, and previews at most four with the
full count. Selecting any item opens that agent's existing inspector by
structured agent ID.

The app does **not** know a root cause merely because a run failed; it says
"Cause not reported here" rather than inventing a diagnosis. During
Paperclip stale/disconnected status the digest is unavailable, not a cached
live alert. The pending-approval shortcut remains separately company-wide.
These are **in-app signals only**, not new macOS notifications: existing
permission-gated, state-transition-deduped system notifications remain
unchanged, avoiding duplicate push alerts. There are no backend requests,
new privileges or persistence. QA needs both notch and menu-bar visual checks,
keyboard/VoiceOver tests, agent tap-through and stale/recovery trials before
this draft can merge; public distribution remains blocked.

## Launch at Login and private connector transport (PC-022)

In the Startup section, Launch at Login is an explicit macOS
ServiceManagement.SMAppService.mainApp opt-in, never a custom launch agent.
The UI reads actual OS registration state; the app never auto-registers.
When System Settings approval is required, the settings explain it.
Swift run and temporary numbered QA bundles intentionally cannot register
a disposable path as a persistent login item. Test the OS toggle in a
final installed signed candidate, not the temporary QA bundle.

Paperclip URLs now require HTTPS outside loopback. An SSH-forwarded
http://127.0.0.1:3100, http://localhost:3100 or [::1] continues working.
Unencrypted HTTP to remote LAN/VPN hosts is rejected; use HTTPS with a
valid certificate and private VPN. Credentialed URLs and query/fragment
secrets remain forbidden. Pixel Companion does not acquire auth tokens,
install certificates or change Paperclip itself. These transport edits
require security approval per PC-000 before merge.

## Structured task drilldown (PC-023)

Pixel Companion now maps the existing Paperclip issues GET response into
bounded read-only TaskSnapshot records (stable issue ID, public identifier,
title, status, structured assigneeAgentId and last reported timestamp).
A collapsible Company tasks section appears in Activity; expand it to search
by identifier/title/status. The task preview is capped at 12 and never makes
additional network calls. Clicking a task only opens an Agent inspector if
its authoritative assigneeAgentId matches a currently reported agent.
Unassigned or unknown agents are not guessed from text.

Each agent inspector also shows at most five explicitly assigned recent
tasks and a total count. Both screens require a fresh connector feed;
unknown or stale assignments cannot appear as live. Full logs and
departments are not assumed from unsupported Paperclip fields. A future
separately reviewed connector can add richer task detail without replacing
these read-only capabilities. TaskSource/ConnectorSnapshot public API changes
require independent PC-000 security review before any merge/release.

## Optional public GitHub CI pulse (PC-024)

Settings offers a blank-by-default Public GitHub repository field. Only a
validated **owner/repo** is accepted. When explicitly configured, Overview
shows at most three latest public GitHub Actions workflow runs and three
open PRs, from fixed api.github.com HTTPS GET URLs. A separate 180-second
refresh timer limits consumption to approximately 40 unauthenticated
requests per hour (when healthy); there are no tokens, auth cookies, arbitrary
URLs, account logins, private repository data, PR changes or workflow
dispatches. A 403/404 or outage removes any cached green indicator rather
than masquerading as live success, and rate limits show an explicit warning.
GitHub status is optional and never blocks Paperclip monitoring.

This is only a public-repository read-only monitor. Private repos, reviews,
merges, authenticated CI and GitHub app permissions require a separately
approved optional connector and credential-handling architecture. Human QA
should test manual input, invalid names, rate-limited/unavailable states,
long run names/PR titles and 360pt notch/menu-bar widths.

## Energy-aware Paperclip refresh and wake (PC-025)

Settings has a default-on **Conserve energy in Low Power Mode** toggle.
When macOS Low Power Mode is enabled, Paperclip's read-only refresh cadence
drops from 5 seconds to 20 seconds. With the toggle off, or with normal
power mode, the 5-second cadence remains. Changing the macOS power state
automatically recomputes the timer without spinning up a second one. Mock
script speed remains exactly user configured and the optional public GitHub
CI source still uses its independent 180-second cadence.

On NSWorkspace wake, the app rechecks the selected presentation/refresh
cadence and requests one ordinary coalesced Paperclip GET refresh. The
connector's existing in-flight guard prevents overlapping requests.
No background privileged agent, additional endpoint, Mac file logging,
or production Paperclip mutation is introduced. Human testing on an actual
battery-powered Mac with Low Power Mode transitions, suspend/resume, both
presentation modes and notifications is still required before merge.

## Verified role groups in Agents (PC-026)

Agents adds List / By role layout switching, in addition to the existing
local search, All/Active filter and read-only inspector. Grouping is only by
the optional structured agent.role reported in Paperclip's already-retrieved
agent response. Role spelling/case is normalized for grouping; the original
role is preserved in the inspector as Reported role. Missing role data
is labeled Role not reported and is never assigned a department inferred
from names or titles. Switching grouping does not requery the network or
change agent IDs/sessions, and the existing fresh-feed guard suppresses
unverified live groups.

Role is not department. Company/department hierarchy navigation remains a
separate feature until Paperclip or another reviewed connector exposes
structured department IDs. This public model field is subject to independent
PC-000 review before merge; Mac visual/VoiceOver acceptance is still needed.

## Canonical Live Activity foundation (PC-027)

CompanionLiveSignal introduces an additive versioned source/entity-identified
read-only event envelope, optional reported progress and explicit semantic
kind. Only valid numerator/denominator pairs become progress.
The deterministic priority resolver prefers security, owner approvals,
infrastructure alerts, agent failures, budget warnings, specific work,
ordinary work, recent completion. It deduplicates current activity
against recent history and rejects live status when stale/offline.
Terminal task failures/completions expire from the primary live surface
after 90 seconds. An active backend agent failure is separately retained.

The character now understands thinking/coding/testing/reviewing/success,
budget-warning/infrastructure/security as source-reported values, keeping
the original five stable moods as fallback. Paperclip structured issue
status maps to working/completed/failed, but task names cannot turn into
coding/testing/security signals. Overview displays a bounded single-row
Live Activity digest with the highest-priority source signal and a count
of others. No new network, notifications, approval actions or privileges.

The initial schema/priority/character is not the entire issue #61.
Distinct character artwork, event stream providers, automatic transient
collapse animation, a personality-disable setting and physical Mac
VoiceOver/360pt/440pt verification remain open. QA24 remains installed
until a new signed local QA has successfully launched.

## Context confidence and conservative fresh-session guidance (PC-028)

The new read-only ContextHealth engine models exact/provider-reported/
estimated/unknown confidence and refuses to invent usage when the runtime
does not supply both a valid context-used count and actual context window.
It uses reported occupancy thresholds (70% watch, 85% suggest a fresh
session, 95% strongly recommend). If genuinely supplied by a future
connector, multiple compactions, a material task change, or unusually large
recent tool output can strengthen the recommendation. Missing signal data
is never interpreted as a reported event.

Paperclip's existing usage counts are labeled provider-reported, not
verifiably exact. The Context Health text is available in Usage and the
agent's session monitor. It does not calculate context from cumulative run
tokens, project budgets or elapsed time. There is deliberately **no New
Chat / Handoff action** until a backend authorizes the operation and a
real ChatBackend supports session creation. Spec-parity #58 remains open for
a full authenticated server-produced handoff, richer provider data, and
real Mac accessibility acceptance.

## Optional standalone Focus/Pomodoro timer (PC-029)

**Settings → Standalone utilities → Enable Focus timer** exposes a compact
Overview panel with a 25-minute focus session, a 5-minute break and a
15-minute break. It is **off by default** and works in standalone Mock mode,
with no Paperclip, GitHub, Pixel HQ or other account. Start/Pause/Resume/Reset
are explicit user actions; switching modes resets the timer and sessions never
restart or move to the next phase automatically.

The running timer is entirely memory-resident, calculates remaining time
from an actual wall-clock deadline, and retains its state while switching
tabs or moving between notch and menu bar. A single one-second UI timer runs
only while active. The normal macOS wake handler reconciles elapsed time
after sleep. Disabling the utility stops and clears the session. Only the
nonsecret on/off preference is stored; no timers, history, calendar events,
clipboard contents, local files, new permissions, notifications or backend
requests are created. No background execution or notification after quitting
is promised.

This is the first native-utility slice of [#62](https://github.com/GrimClawBot/Pixel-Companion/issues/62);
Now Playing, calendar, system HUDs and other optional modules remain open.
Real 360pt/440pt notch/menu bar keyboard, VoiceOver and sleep/wake tests
remain human acceptance gates; this draft must not be publicly released.

## Optional Battery & Power HUD (PC-030)

Settings → Standalone utilities → Enable Battery & Power HUD adds a
compact read-only Overview indicator on any Mac, independent of
Pixel HQ/Paperclip and the Focus timer. The widget is OFF by default.
While enabled, the app uses Apple's public IOKit Power Sources APIs to
read internal battery level (if present and valid), whether charging is
explicitly reported, adapter versus battery power when reported, and
ProcessInfo's Low Power Mode status. No additional entitlement, login,
credentials, network requests, OS notifications, private APIs or helper
is required.

The monitor runs one 30-second refresh timer only while enabled, refreshes
on macOS wake and Low Power Mode changes, and stops/clears in-memory
readings when the user disables the module. It never saves a history,
serial number or device identity. An absent battery, malformed percentage,
unknown charging state or unavailable power source remains unavailable
rather than fabricated. Current Mac settings for Paperclip, GitHub, Focus,
notifications and the Power conservation cadence are not changed.

This is the battery *panel* slice of spec-parity issue #62; global volume
or brightness overlays, system Now Playing and calendar integrations remain
separate open tasks. Before release, physically test actual Mac battery/
adapter transitions, Low Power Mode changes, both 360pt/440pt layouts,
keyboard and VoiceOver, and an external Mac without a battery.

## Optional private next Calendar event (PC-031)

In Settings → Standalone utilities, Enable Calendar widget is OFF by default.
Enabling **does not request macOS Calendar permission**. The Overview card
then offers an explicit Grant Calendar access… button, which requests
EventKit full read access only when clicked. A packaged app includes the
NSCalendarsFullAccessUsageDescription reason. An unbundled swift-run
process deliberately cannot request access without that usage description.

When full access is authorized, the widget reads only the next upcoming
calendar event from macOS EventKit, using a seven-calendar-day bounded
window. A currently ongoing all-day event is a fallback if no future event
exists. It shows event start time/all-day status and initially masks the
title as "Calendar event"; Show event titles is a SEPARATE default-OFF
setting. It neither shows nor stores attendees, location, calendar source,
event IDs, notes or descriptions. Event summaries remain in RAM only,
are cleared when the widget is disabled or Calendar permission becomes
unavailable, and are never sent to Pixel HQ, Paperclip, GitHub or files.

Full-access permission can be denied/restricted by macOS. The view
honestly reports unavailable/denied/restricted/empty states and does not
prompt automatically on first app launch, waking, or enabling Settings.
The calendar source refreshes at most every 120 seconds while both
enabled and authorized and on normal macOS wake. It does not create,
modify, delete or accept Calendar invitations; no additional network
clients, entitlement or background daemon are introduced.

This is a limited third native-utility slice of original-spec issue #62.
Real physical macOS calendar grant/deny/revoke, multiple calendars,
recurring/all-day event, 360pt/440pt Mac UI/VoiceOver and privacy
acceptance remain release gates. No request for actual Calendar
permission occurs in automated tests or during QA package installation.

## Optional Apple Music Now Playing (PC-032)

Apple Music Now Playing is OFF by default in Settings / Standalone
utilities. Enabling it does not contact Music or request Apple Events
Automation permission. The Overview card provides a separate, explicit
Connect to Apple Music button. Only that user interaction may request
permission via the read-only NSAppleScript Music.app player-state and
track metadata interface. The packaged app declares a reason in
NSAppleEventsUsageDescription. Without this reason, nonpackaged swift-run
must fail closed. Pixel Companion does not launch the Music app.

The connector reads playing/paused/stopped status and optionally current
song title, artist and album, without any playback commands or access to
library/playlist history. Song details are separately hidden by default.
Reading resumes only after an explicit connection within the current app
session, every 30 seconds while enabled, and after Mac wake. Disabling
clears RAM-only metadata and stops polling. Reopening Pixel Companion
requires connecting again; denial and unavailable Music stay explicit.

This is Music.app ONLY. Apple's documented MPNowPlayingInfoCenter is for
publishing the app's own media metadata, not reading a global third-party
media session. Pixel Companion does not use the private MediaRemote
framework or claim Spotify/browser support. Future provider adapters
require separate opt-in, compatibility tests and security review.

Physical macOS Automation prompt/deny/revoke tests and actual Apple Music
play/pause/stopped playback, VoiceOver, 360pt/440pt hardware layouts and
signing entitlement review remain mandatory before merge or distribution.
No Apple Events are executed in the deterministic tests.

## Read-only output volume HUD (PC-033 draft)

Settings → Standalone utilities → **Enable Output volume HUD** is OFF by default.
When enabled, the Overview card shows only the default macOS audio output device’s
reported master volume percentage and reported mute flag, read with public CoreAudio
GET-only APIs. Devices without a readable master scalar display **unavailable**;
missing mute-state reports remain unknown. The feature does not capture audio, ask for
microphone access, change system sound, or persist any volume/device history. It polls
periodically every 10 seconds, stops and clears on disable, and refreshes after wake.
Human QA of physical output types and both layouts remains a separate release gate.

## Read-only display brightness HUD (PC-034 draft)

Settings → Standalone utilities → **Enable Display brightness HUD** is OFF by default.
This reports only a validated scalar read from the public IOKit display-brightness
property when exactly one display service is identified. It intentionally does
not use private DisplayServices/CoreDisplay APIs or claim to support all modern
internal/external displays. If there are multiple candidate services, no
readable brightness parameter, or an invalid scalar, the Overview card clearly
reports **unavailable**. It never sets display brightness, accesses screen
pixels, requests capture/Accessibility permissions or writes history. One
local poll every 15 seconds only while enabled; state cleared immediately
on disable, and refreshed on wake. Physical multi-display and VoiceOver QA
remains outstanding.

## Download progress contract (PC-035, provider integration pending)

The optional Downloads Overview card is OFF by default. It intentionally does not
scan browser histories, Safari, ~/Downloads, the filesystem, or the network. macOS
offers no public universal progress feed for third-party downloads. The app defines
a small opt-in DownloadProgressSource adapter interface for a future reviewed
integration to report validated bytes received and total. Until a source is
registered, the card reads No download integration connected. If the source
doesn't report a total, no percentage is invented. Only counters reach this UI:
filenames, URLs and tokens are neither read nor retained. This is a source
contract and HUD, not a claim that system-wide downloads are already tracked.

## Native design refresh (PC-036 draft)

Settings now uses a native macOS resizable window with a sidebar for General,
Connections, Utilities and Notifications. All settings remain bound to their
original controls; selecting a sidebar row does not request permissions or alter
the active connector. Utilities are grouped into Productivity, Mac status and
Personal instead of one long fixed-height form. The notch/menu bar shares the
same accessible tabs and semantic system card surfaces. The UI respects Light/
Dark Mode, Reduce Transparency and Reduce Motion; final VoiceOver, large text
and real-window visual QA are still required before release.

## Transient file shelf (PC-037 draft)

Settings → Utilities → File shelf is OFF by default. Once enabled, Overview allows an explicit macOS file picker. Only up to eight unique local file URLs and sanitized short display names are held **in RAM**, for use with optional Reveal in Finder. The app does not copy, read, index, upload, bookmark or persist these files or send them to Paperclip/Pixel. Disable or quit to clear them. Drag/drop and AirDrop are not connected yet; evaluate only after separate privacy review. Manual narrow-layout, NSOpenPanel and VoiceOver tests remain necessary.

## Finder drop and explicit native sharing (PC-038 draft)

In the opt-in File shelf, Finder file URLs may be dragged onto the shelf card. Dropped web links, actual directories (even without a trailing slash), duplicates and over-limit URLs are rejected. A native macOS Share action on each item exposes the OS sharing interface, where the human may choose AirDrop when available. Selecting a recipient or other share destination is a user action: Pixel Companion never automatically sends a file. The OS sharing service may read/transmit a chosen file **only after the user explicitly shares it**. macOS/system UI and permissions remain authoritative. Validate actual Finder drag/drop and AirDrop recipient sheet on Mac before accepting this feature.

## Manual RAM-only clipboard text shelf (PC-039 draft)

Settings → Utilities → Clipboard (manual capture) is OFF by default. Pixel Companion **does not monitor NSPasteboard**. Only when the user presses Save copied text does the app check recognized concealed/transient/password-manager pasteboard type markers, then read a plain-text string if allowed. It holds at most 5 bounded, display-sanitized snippets in RAM. Re-copy and remove happen only when clicked. Disable or quit clears them, and nothing is written to disk, sent to Paperclip/Pixel or logged. **Warning:** Some apps put passwords on the clipboard without marking them secret, which cannot be reliably detected; do not manually save passwords or sensitive data. This is not a credential manager.

## Local agent status bridge (PC-040 draft)

This is a working **read-only local status file transport**, NOT automatic
Claude Code/Codex/Hermes session discovery. Enable Settings → Connections →
Local agent sessions and explicitly choose a JSON file. No directory scanning,
process discovery, CLI execution, transcripts, prompts or credential access.
The file path is RAM-only and forgotten on disable/quit. In the Agents tab,
Local agents appear **separately** from authoritative Paperclip company agents.

A trusted local source can publish actual status using the optional one-shot
status writer provided in this repository. Example:

    python3 scripts/local_agent_feed_writer.py \
      --output /tmp/local-agent-status.json \
      --session codex codex-local running "Codex" \
      --session claude-code claude-local waiting "Claude Code"

Select that JSON file in Settings. Re-run the command whenever the agent's
**actual** reported status changes, and refresh every two minutes for current
status. The writer itself does NOT inspect Codex/Claude/Hermes sessions, so
the caller is responsible for truthful status and fresh timestamps. No agent
hooks are installed automatically. Hook/IPC/source-specific integrations
require separate design and security review before enabling.

Status schema version 1 uses these fields: schemaVersion=1 and sessions
array with id, source, name, state and updatedAt (RFC3339/ISO8601 UTC). Source:
codex, claude-code, hermes, custom. State: running, waiting, idle,
completed, failed. Maximum 12 sessions, 64 KiB file, bounded IDs and labels,
no prompt, token or task data. Status older than 120 seconds is visibly
stale; timestamps over 30 seconds in the future and malformed reports fail
closed. The app opens only one manually selected regular file, rejecting
symlinks and special devices, GET-only. The optional writer publishes with
atomic replacement and mode 0600. No Pixel HQ configuration is required.

## Codex process presence (PC-041; local QA only)

Settings → Connections → **Detect Codex process on this Mac** is OFF by
default. Once explicitly enabled, the app uses the public macOS BSD
KERN_PROC_ALL sysctl process metadata interface, filtered to the current
user and an exact process name of "codex". It refreshes at most once every
15 seconds, and clears the reading immediately on disable. The card in
Agents shows only whether one or more Codex-named processes were found,
or an unavailable status if macOS denied the query.

This is a **direct Codex process presence signal, NOT Codex session
telemetry**. VS Code and other clients may leave their Codex app-server
running while no session is active. A same-named unrelated process could
also be counted. No claim is made about active coding, Codex provider
identity/signature, sessions, prompts, tokens, context or approvals. No
arguments, PIDs, executable paths or histories are stored or displayed.
Pixel Companion does not call Codex CLI, inspect ~/.codex, or use private
libproc APIs. The explicit status-feed transport from PC-040 remains a
separate optional integration, and Paperclip data stays authoritative
for company agents.

## Codex turn-completion notifications (PC-042 draft)

Codex's supported top-level notify configuration calls a user-supplied
program at the end of a Codex agent turn. The documented event currently
available is agent-turn-complete, **not** started, running, approval-needed,
success or failure. Pixel Companion never reads raw Codex history or
transcripts. It includes an OPTIONAL Python hook which discards all fields
except event type and the fact that a notification was received.

The hook writes only the fixed filename pixel-companion-codex-turn.json in
a folder you explicitly configure. Create a private folder of your choosing
with mkdir -m 700. Example for Codex config.toml, at its TOP LEVEL
(replace both placeholder absolute paths):

    notify = ["/usr/bin/python3", "/ABSOLUTE/PATH/TO/Pixel-Companion/scripts/codex_notify_bridge.py", "--directory", "/ABSOLUTE/PRIVATE/EVENT/FOLDER"]

**Do not overwrite an existing notify configuration:** Codex supports one
top-level notify program; compose a safe dispatcher if another integration
already uses it. This build NEVER writes to your Codex config automatically,
installs a hook, starts Codex or modifies existing controls. The event
script receives one raw notification JSON argument (which can carry
sensitive content) solely to detect the supported event. It never prints,
stores, transmits, hashes or forwards prompts, assistant answers, workspace
paths, session/turn IDs, tokens or any other incoming payload fields. The
marker is atomically written mode 0600. No network dependency. The hook is
only active when a compatible Codex runtime invokes its configured notify.
In particular, do not assume the VS Code Codex app-server emits CLI notify
events without confirming that provider's behavior.

Then enable Settings → Connections → Show Codex turn completions and select
the same event FOLDER (not a file). The app watches only the expected fixed
filename in that user-chosen directory. Until the first event, it shows
No valid turn-completion event available. A valid timestamp is displayed
as recent only for two minutes, otherwise Previous turn completion (not live).
Event source authenticity is not cryptographically guaranteed; another
process with write access to that local folder could forge this marker.

**Turning the Pixel Companion display off forgets its folder immediately,
but does not remove or stop a separately installed Codex notify hook.**
To fully stop event-file writes, remove the external notify setting yourself.
The marker file stays on disk until you remove it; it contains only the
event type and timestamp. Private directories and explicit local consent
remain important. No credentials are stored or transmitted by Pixel Companion.

## Claude Code lifecycle hook bridge (PC-043 draft)

Claude Code supports user-defined command hooks in a settings JSON file
and sends event payload JSON over standard input. This feature is an
**optional, privacy-scrubbed lifecycle signal**, not a transcript reader
or full Claude Code API connector.

Supported observed milestones are SessionStart (begins or resumes),
UserPromptSubmit (prompt was submitted, NOT verified processing),
Stop (Claude finished responding, NOT task success), StopFailure (the
turn ended due to an API error), and SessionEnd (session terminated).
Only event type and local UTC observed time are retained. Prompt text,
tool inputs, cwd, session_id, transcript_path, responses and errors
are never retained, written, sent or printed.

To opt in, create an existing private folder yourself (chmod 700).
Then, in your own ~/.claude/settings.json or a single project's
.claude/settings.local.json, ADD hook groups to the existing hooks map.
The following is a configuration example, not something Pixel
Companion automatically installs. Substitute the absolute script and
folder paths. Keep any existing hook settings and review with Claude
Code's /hooks menu. The example uses command hooks without matchers:

    {
      "hooks": {
        "SessionStart": [{"hooks": [{"type": "command", "command": "python3 /ABSOLUTE/PATH/TO/Pixel-Companion/scripts/claude_hook_bridge.py --directory /ABSOLUTE/PRIVATE/EVENT/FOLDER"}]}],
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "python3 /ABSOLUTE/PATH/TO/Pixel-Companion/scripts/claude_hook_bridge.py --directory /ABSOLUTE/PRIVATE/EVENT/FOLDER"}]}],
        "Stop": [{"hooks": [{"type": "command", "command": "python3 /ABSOLUTE/PATH/TO/Pixel-Companion/scripts/claude_hook_bridge.py --directory /ABSOLUTE/PRIVATE/EVENT/FOLDER"}]}],
        "StopFailure": [{"hooks": [{"type": "command", "command": "python3 /ABSOLUTE/PATH/TO/Pixel-Companion/scripts/claude_hook_bridge.py --directory /ABSOLUTE/PRIVATE/EVENT/FOLDER"}]}],
        "SessionEnd": [{"hooks": [{"type": "command", "command": "python3 /ABSOLUTE/PATH/TO/Pixel-Companion/scripts/claude_hook_bridge.py --directory /ABSOLUTE/PRIVATE/EVENT/FOLDER"}]}]
      }
    }

Do not replace existing settings or manually edit managed policy files;
add this only where you have permission and explicitly want it. The
hook runs with your Claude Code environment's local privileges and
must be treated as code. The Python script reads at most 256 KiB from
stdin, parses only hook_event_name in its allowlist, and always exits 0
without stdout, stderr, an approval decision or permission change.
The fixed status marker pixel-companion-claude-event.json is replaced
atomically with file mode 0600 and holds one event type and timestamp.
Unrecognized events cause no writes. Its contents remain on disk until
you remove the marker or folder. As with any local non-cryptographic
marker, another process with write access could forge it.

Next enable Settings -> Connections -> Show Claude Code lifecycle
events and choose the SAME folder via the macOS picker. The app reads
only that fixed expected file, without directory crawling, scanning
~/.claude, running Claude CLI, reading prompts, accessing credentials,
or sending network traffic. It polls only while enabled and connected;
the location stays in RAM and is forgotten on quit/disable. Events
older than two minutes are marked historical, not live. Turning off
the in-app toggle does not remove hooks you configured separately.
Manual real-Claude-hook delivery, narrow/notch and VoiceOver QA and
security review remain required before considering the integration
fully proven.

## Unified local AI activity (PC-044)

The Activity tab also displays a separate **Local AI activity** card when
either previously implemented, OFF-by-default Codex/Claude hook feed is
enabled. It combines ONLY the already-scrubbed event type and local UTC
timestamp from those two sources, sorted newest-first, with source filters.
No Paperclip company events are mixed in or given local origin labels.

This is best-effort, **not a complete or authoritative agent audit history**.
The underlying optional hook publisher files each contain just the MOST
RECENT event, so multiple events that occur between 15-second polls can
be missed. The app stores up to 20 observed changes in RAM; it retains a
30-minute window and shows recent vs historical signals distinctly.
On repeated polls of the same timestamp+event, it suppresses duplicates.
Events that were already older than two minutes when first observed
are not replayed into the timeline. Events are cleared per-source on
disable, disconnect or unavailable status, and all history disappears
when the app exits. No local history files, prompts, transcripts,
workspace identifiers, approvals, token usage or credentials are saved
by Pixel Companion. Disabling the in-app display does NOT remove any
separately configured hook (see PC-042 and PC-043 notes).

## Local AI attention + notifications (PC-045)

The Overview tab adds a read-only Local AI attention digest when either
Codex/Claude hook monitor is enabled. It shows the most recent two *observed*
Codex turn-ending or Claude response-ending / API-error markers, and a button
to navigate to the independent Local AI activity timeline. There is no agent
control, task/approval inference, provider API connection or new filesystem
read. This does not show raw text, paths, timestamps in notification payloads,
session IDs, transcripts, tokens or private messages.

**OS notifications are a separate, default-OFF opt-in**: Settings ->
Notifications -> System notifications AND Local agent alerts must BOTH be on,
and macOS must actually grant permission. Turning on Local agent alerts by
itself does NOT request permissions or enable the global notifications toggle.
Only Codex turn ends and Claude response ends/API error ends are eligible;
Claude prompt submit and session start/end are never alerted. Generic, static
banner titles/bodies contain no identity/task/workspace information.
Notification sending is limited to once per 90 seconds and only for freshly
observed eligible events (no replay on enable, app launch, disconnect, stale
marker, denied/pending permission or later permission grant). Pending local
alerts are NEVER queued while macOS has denied or not yet granted permission.
The existing Paperclip approvals/agent-run notification detector, private
boundaries and QA simulation controls are unchanged. Hook sources still
require separate explicit configuration outside the app; no hook is
automatically installed. App never writes to Codex/Claude configs.
