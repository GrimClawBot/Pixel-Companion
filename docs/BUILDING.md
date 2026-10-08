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
