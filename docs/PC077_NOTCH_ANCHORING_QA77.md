# PC-077 — Pixel-aligned hardware-notch anchoring and QA77

## Why

QA76 proved the compact character/status now appears beneath the MacBook camera
cutout. Previously we estimated the camera housing's horizontal position
from the **widths** of AppKit's left and right top auxiliary areas. That
assumed both auxiliary rectangles began exactly at the display's side edges.

AppKit reports the actual `auxiliaryTopLeftArea` and
`auxiliaryTopRightArea` as **rectangles in global screen coordinates**.
We now derive the gap from `left.maxX` and `right.minX`, validate both
reported side regions and the safe-area top inset, and align the housing
edges/panel origin to the display's reported `backingScaleFactor` pixel grid.

Official Apple references:
- https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc
- https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea-gr2n
- https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets

## Exact behavior and scope

- `PresentationCoordinator` now passes the *full, actual* AppKit auxiliary
  rectangles and Retina backing scale to a new additive
  `NotchGeometry` initializer. The prior width-based initializer remains
  available for callers, fixtures and compatibility.
- `NotchGeometry` positions the compact panel using global reported
  left/right **edge positions**, including screens whose origins are
  negative or offset above/below the primary display. It snaps those edges
  and the panel's horizontal origin to whole backing pixels to minimize
  visible seams between black surfaces.
- Inconsistent source data (missing/notched-out safe inset, missing areas,
  overlapping, displaced top rectangles, invalid bounds, zero/NaN scale)
  **does not create a fake notch**. The established menu-bar fallback then
  applies rather than placing an overlay over ordinary macOS menu items.
- Mouse hover/click/dismiss, expanded snapshot/detail widths, the QA76
  compact layout and status character, settings/permissions, all accepted
  tools, read-only connectors and UI tabs are unchanged.
- The physical camera cutout is not a controllable display. This remains
  a borderless, nonactivating macOS panel drawn **around** that hardware.
  There is no private API, entitlement, jailbreak, camera manipulation or
  display reconfiguration.

## Local QA77 installation

Quit QA76 using the app's Quit control first. Do **not** delete QA76,
QA74, QA72 or QA61. Clone the draft source separately and build on the
owner's Mac:

```bash
mkdir -p "$HOME/Developer" &&
git clone --depth 1 --branch pc-077/screen-edge-notch-anchoring \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA77" &&
bash "$HOME/Developer/Pixel-Companion-QA77/scripts/qa_preview_macos.sh" --qa-number 77
```

Optional no-write preview:

```bash
bash "$HOME/Developer/Pixel-Companion-QA77/scripts/qa_preview_macos.sh" \
  --qa-number 77 --print-plan
```

The existing hardened script builds **only**
`~/Applications/Pixel Companion QA Update 77.app`, refusing existing
files and symlinks at that path. The new QA77 marker is added to a
separate private Info.plist before offline ad-hoc signing; its
signature and `PCQAUpdateNumber=77` are checked before launch.
Temporary QA bundles cannot enable real macOS Launch at Login. No
GitHub Release, public binary, automated removal, remote Mac deployment,
Paperclip mutation or protected-main merge is performed.

All temporary QA apps use the same bundle identifier and may share local
settings. Do not run two at once or assume separate authentication data.

## Real Mac acceptance checklist

1. Settings → General shows `0.1.0 (build 77)` and `QA Update #77`.
   Launch at Login stays disabled.
2. Compare the collapsed notch against QA76 at the same screen scaling.
   Verify the black extension meets the physical camera housing cleanly,
   is centered precisely below it, and does **not** cover neighboring
   Apple menu-bar controls.
3. Hover/click/dismiss and switch compact/snapshot/detail. Check
   expanded content sizing, character, readable status and correct
   alerts remain intact.
4. Change the built-in screen's macOS display scaling, sleep/wake, attach
   and detach an external monitor, close the lid, and check the app's
   existing menu-bar fallback when no display reports a camera cutout.
5. Test fullscreen/Space changes, VoiceOver/keyboard navigation, dark UI,
   Reduce Motion, long status labels, missing/stale Paperclip telemetry,
   and secondary display with negative global screen coordinates.
6. Verify no startup preference changes, no unexpected app deletion,
   and no credential/approval/server writes during visual QA.

## Rollback

Quit QA77. To reopen untouched QA76:

```bash
open -n "$HOME/Applications/Pixel Companion QA Update 76.app"
```

If QA76 lives elsewhere, open that verified path. No unattended cleanup.

## Quality and approvals

Native GitHub CI must pass tests, SwiftLint, warnings-as-errors build and
secrets/config checks at the **exact PR head**. Tests cannot substitute for
real camera-housing alignment on the owner's Mac. Greptile technical
review, independent human GitHub approval, Mac acceptance, owner-authorized
protected integration and public distribution are all separate gates.
