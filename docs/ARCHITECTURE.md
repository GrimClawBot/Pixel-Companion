# Architecture

Pixel Companion is a single Swift package with no third-party dependencies.

```
Package.swift
├── Sources/PixelCompanionCore   library, Foundation + CoreGraphics only (no AppKit; also builds on Linux)
│   ├── Connector/               connector protocols, models, snapshot, registry
│   ├── Mock/                    MockConnector and MockScript
│   ├── Character/               CharacterMood, CharacterStateMachine, CharacterSprite
│   ├── Settings/                SettingsStore (UserDefaults)
│   └── Presentation/            NotchGeometry, PresentationMode, NotchInteraction
├── Sources/PixelCompanion       macOS app: AppKit + SwiftUI shell
└── Tests/PixelCompanionCoreTests
```

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

## Character art

`CharacterSprite` holds original 12 × 10 pixel art drawn for this project: a small round blob whose
eyes, mouth, accent and feet change per mood, with two animation frames each. The menu bar uses
the mood's SF Symbol instead. No third-party character assets are used.

## Boundaries

- Read-only: no protocol can change state on a backing service.
- No credentials, keychain, endpoints, deployment or org structure in the app.
- No `Info.plist` or entitlements: the app runs as a SwiftPM executable and sets its accessory
  activation policy (no Dock icon) at launch.
