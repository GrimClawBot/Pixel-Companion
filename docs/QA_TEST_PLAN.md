# QA test plan: PC-001 notch shell + MockConnector

Hand-off for QUALITY_GATE.md §4. Run on a real Mac after native checks pass and Greptile is
clean. Record the build SHA (`git rev-parse HEAD`), macOS version and hardware on the issue with
the evidence.

## Setup

```sh
git checkout <SHA under test>
defaults delete PixelCompanion 2>/dev/null   # start from default settings
swift run -c release PixelCompanion
```

Defaults: connector **Mock: demo loop**, connection **Connected**, step every **4 s**,
presentation **Automatic**.

## Hardware matrix

| Run | Hardware                                          | Expected placement       |
|-----|---------------------------------------------------|--------------------------|
| A   | MacBook with a notch (14"/16" MacBook Pro, 13"/15" MacBook Air M2 or later), built-in display only | Notch |
| B   | Mac without a notch (Intel MacBook, M1 MacBook Air/Pro, iMac, Mac mini with an external display) | Menu bar |
| C   | Run A's MacBook plus an external display, lid open | Notch on the built-in display |
| D   | Run A's MacBook, lid closed on the external display (clamshell) | Menu bar |

## Cases

Capture a screenshot (⇧⌘4, then Space to grab a window, or a region for the notch) for every
row marked 📸.

| # | Steps | Expected |
|---|-------|----------|
| 1 | Launch (run A). | No Dock icon. A black strip extends the notch with the character on the left and a status symbol on the right. 📸 compact |
| 2 | Hover the strip. | It expands below the notch: character, mood, connector line, current activity and usage bar. 📸 snapshot |
| 3 | Move the pointer away. | It collapses to the compact strip. |
| 4 | Click the strip. | Detail view: snapshot, activity list (newest first), messages, **Read-only** label, **Settings…** and **Quit**. 📸 detail |
| 5 | With detail open, move the pointer away. | Detail stays open. |
| 6 | Press Esc; reopen and click another app's window. | Each collapses the detail view to compact. |
| 7 | Watch the demo loop (about 32 s at 4 s per step). | The character moves idle → working → working → waiting for approval (orange badge with a count in the compact strip) → working → error → working → idle, and the sprite animates in every state. 📸 one per mood: idle, working, waiting for approval, error |
| 8 | Settings… → Connection: Connecting, then Disconnected. | Character turns grey, eyes closed (offline); the script stops advancing. 📸 offline |
| 9 | Connection: Error. | Error character; the status line reads "Simulated connection error". |
| 10 | Connection: Connected. | The script resumes from where it stopped. |
| 11 | Connector: **Mock: quiet**. | Idle character; activity "All quiet". |
| 12 | Connector: **None**. | Offline character, "No connector", no activity; mock controls are disabled. The app keeps working. |
| 13 | Next-step stepper: 1 s, then 30 s. | Steps speed up / slow down accordingly. **Restart script** returns to "Ready". |
| 14 | Presentation: **Menu bar**. | The notch strip disappears; a menu-bar symbol for the mood appears. Hover shows a tooltip (mood · activity); click opens the detail popover. 📸 menu bar + popover |
| 15 | Presentation: **Notch**, then **Automatic**. | The notch strip returns and the menu-bar item is removed. "Now showing in" matches. |
| 16 | Quit, relaunch. | All settings from 11–15 persist. |
| 17 | Run B: launch with Presentation **Automatic** and **Notch**. | Menu bar in both; Settings explains no notch display is connected. |
| 18 | Run C: connect / disconnect the external display; change its arrangement so it is the main display. | The strip stays centred on the built-in notch and never lands on the external display. |
| 19 | Run D: close the lid, then open it again. | Menu bar while closed; notch strip returns within about a second of opening. |
| 20 | Sleep (Apple menu ▸ Sleep), wake after 10 s or more. | Same placement as before sleep, correctly positioned, still updating. |
| 21 | Enter a full-screen app, then switch Spaces. | The notch strip stays visible on every Space, over the full-screen app. |
| 22 | Quit from the detail view. | Process exits; no notch strip or menu-bar item remains. |

## Permissions and safety

- No permission prompts are expected (the outside-click monitor uses mouse events only, which
  need no Accessibility permission). Any prompt is a failure.
- Read-only: no case should trigger network traffic. Optional check: Little Snitch / `nettop -p
  PixelCompanion` shows no connections.

## Regression areas

- Pointer flicker at the edge of the expanded panel (rapid enter/exit).
- The menu bar under the panel stays clickable when it is compact (the panel only covers the
  notch strip).
- Any area Greptile flags on the final SHA.
