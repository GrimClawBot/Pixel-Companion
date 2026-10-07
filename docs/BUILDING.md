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
replacement fails. It refuses to overwrite existing custom destinations. No app is published or
notarized. A macOS permission prompt should only appear when a feature explicitly requests it;
the current read-only features do not request notification permission.

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
