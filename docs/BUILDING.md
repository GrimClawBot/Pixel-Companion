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
