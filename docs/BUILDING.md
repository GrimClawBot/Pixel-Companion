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
