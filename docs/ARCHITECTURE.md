# Architecture

Pixel Companion is a single Swift package with no third-party dependencies.

```
Package.swift
├── Sources/PixelCompanionCore   library, Foundation + CoreGraphics only (no AppKit; headless-testable)
│   ├── Connector/               connector protocols, models, snapshot, registry
│   ├── Mock/                    MockConnector and MockScript
│   ├── Character/               CharacterMood, CharacterStateMachine, CharacterSprite
│   ├── Settings/                SettingsStore (UserDefaults)
│   └── Presentation/            NotchGeometry, PresentationMode, NotchInteraction
├── Sources/PixelCompanion       AppKit + SwiftUI app shell
├── Tests/PixelCompanionCoreTests
└── Tests/PixelCompanionAppTests
```

The package now includes both the platform-neutral core and the native macOS app shell.

All decisions live in `PixelCompanionCore` as plain values and pure functions, so they can be
unit-tested without a display. The app target only adapts AppKit inputs (screens, mouse,
`UserDefaults`, timers) to the core and renders the result.

## Data flow

```
SettingsStore ──► ConnectorRegistry.makeConnector ──► any Connector (MockConnector)
                                                          │ refresh() every step interval
                                                          ▼
                                             ConnectorSnapshot (immutable)
                                                          │
                                      CharacterStateMachine.update(with:)
                                                          ▼
                              mood + snapshot ──► notch panel / menu-bar views
```

1. `SettingsStore` holds the chosen connector, presentation preference, simulated connection state
   and mock step interval.
2. `ConnectorRegistry` builds the connector, or none: the app runs without one.
3. On each step the app calls `refresh()` and captures a `ConnectorSnapshot`.
4. `CharacterStateMachine` turns the snapshot into one of five moods: `idle`, `working`,
   `waitingForApproval`, `error`, `offline`. Precedence: not connected → offline, connection error
   → error, pending approval → waiting, failed activity → error, running activity → working, else
   idle.
5. Views render the snapshot and animate the mood's `CharacterSprite` frames.

See [CONNECTORS.md](CONNECTORS.md) for the connector protocols.

## Presentation

`PresentationMode.resolve(preference:notchAvailable:)` picks where the companion lives:

| Preference  | Notch display present | Result    |
|-------------|-----------------------|-----------|
| Automatic   | yes / no              | notch / menu bar |
| Notch       | yes / no              | notch / menu bar (fallback) |
| Menu bar    | either                | menu bar  |

`NotchGeometry` finds the camera housing from `NSScreen.safeAreaInsets.top` and the widths of
`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. A screen without a top inset or without both
auxiliary areas has no notch, which covers older Macs, external displays and a closed lid.

`NotchInteraction` is the hover and click state machine for the notch panel:

| Surface   | Shows                                    | Enter                    | Leave                          |
|-----------|------------------------------------------|--------------------------|--------------------------------|
| compact   | character and status beside the notch    | start, dismiss           | pointer enters, click          |
| snapshot  | current activity, approvals, usage       | pointer enters (compact) | pointer exits, click, dismiss  |
| detail    | activity feed, chat, settings, quit      | click                    | dismiss (Esc, click outside)   |

## App shell

| Type                       | Role |
|----------------------------|------|
| `PixelCompanionMain`       | Entry point; sets the accessory activation policy (no Dock icon). |
| `AppModel`                 | Owns the connector and step timer; publishes snapshot and mood; reads and writes settings. |
| `PresentationCoordinator`  | Resolves notch vs. menu bar on launch, display changes, wake and settings changes. |
| `NotchPanelController`     | Borderless non-activating `NSPanel` at status-bar level on all Spaces; resizes per `NotchSurface`; hover via an `.activeAlways` tracking area; Esc and outside clicks dismiss. |
| `StatusItemController`     | `NSStatusItem` with the mood symbol, tooltip snapshot and a detail popover. |
| `SettingsWindowController` | SwiftUI settings form in a reusable window. |

## Character art

`CharacterSprite` holds original 12 × 10 pixel art drawn for this project: a small round blob whose
eyes, mouth, accent and feet change per mood, with two animation frames each. The menu bar uses
the mood's SF Symbol instead. No third-party character assets are used.

## Boundaries

- Read-only: no protocol can change state on a backing service.
- No credentials, keychain, endpoints, deployment or org structure in the app.
- No `Info.plist` or entitlements: the app runs as a SwiftPM executable and sets its accessory
  activation policy (no Dock icon) at launch.
