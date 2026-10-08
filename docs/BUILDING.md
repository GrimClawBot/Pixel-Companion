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
