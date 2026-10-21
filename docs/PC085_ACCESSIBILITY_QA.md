# PC-085 accessibility implementation and manual QA

This is an isolated, uncommitted accessibility pass over predecessor planning
head `96adbd5cce0ce0a2dd0731e1ffc69e4a5cc948ec`, in
`/tmp/px017-companion-ui-20261021`. It is not review, release, or QA acceptance
for PR177. PR177, Phase0 hold records and QA rows 18–19 are untouched; Phase1
is not started. No installation, app launch, merge, deployment, commit, push,
service restart, or network tooling was performed for this pass.

The checkout is a detached linked worktree. Naming an independent branch
requires writing Git metadata under the original checkout, outside the permitted
write roots. No branch was created and no original-checkout metadata was changed.
Suggested later branch name: `codex/pc085-accessibility`. No `AGENTS.md` was
present in this checkout or its filesystem ancestors.

## Scope

- Both compact and expanded status buttons use a label configured as one
  accessibility element: status, plus verified pending approvals when present.
  Its child character and SF Symbols are ignored by accessibility. Stale,
  unavailable and connecting feeds omit cached approval counts and working mood.
- The status button has higher accessibility traversal priority than expanded content.
  Opening details has an explicit hint; snapshot content also exposes the named
  action “Open companion details”, alongside its existing pointer gesture.
  Native buttons, keyboard behavior and all content remain available.
- The expanded summary uses the same freshness-aware visible mood and text.
  Its character is decorative and its source/status text is one combined item.
  Section titles expose heading semantics without changing their appearance.
- Settings keeps its native sidebar selection and keyboard order. Categories
  have explicit names and destination hints, the sidebar and form have names,
  and the selected pane title is a heading. Connector permissions and settings
  mutations are unchanged.

## Automated evidence — 2026-10-21

Environment: macOS 26.5.1 (25F80), arm64, Apple Swift 6.3.3.

Tests were written before the new announcement helper. The first focused build
failed because `CompactBarPresentation.accessibilityLabel` did not yet exist.
After implementation:

| Check | Result | Limit |
| --- | --- | --- |
| Focused notch layout, Settings navigation, keyboard tests | 20 passed, 0 failures | Includes two new announcement tests; does not inspect the live AX tree |
| Full Swift package tests (core and app targets), `-warnings-as-errors` | 549 passed, 0 failures | Native AppKit/SwiftUI compilation succeeded; no installed app was exercised |
| SwiftLint strict, four changed Swift files | 0 violations | Other source files were not linted |
| `git diff --check` | Passed | Formatting only |

Reproduce from this checkout (zero package dependencies; automatic resolution
disabled; build products and caches stay local):

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox \
  --cache-path .build/cache --config-path .build/config \
  --security-path .build/security --disable-automatic-resolution \
  -Xswiftc -warnings-as-errors

swiftlint lint --strict --no-cache \
  Sources/PixelCompanion/Notch/NotchViews.swift \
  Sources/PixelCompanion/Settings/SettingsView.swift \
  Sources/PixelCompanion/Views/CompanionViews.swift \
  Tests/PixelCompanionAppTests/NotchLayoutTests.swift
git diff --check
```

For the focused run, add
`--filter 'NotchLayoutTests|SettingsNavigationTests|CompanionKeyboardNavigationTests'`
to the Swift command. SwiftPM's nested sandbox was disabled for local tooling;
the session's filesystem/network restrictions remain applicable. An attempted
additional network-denying `sandbox-exec` wrapper could not initialize
(`sandbox_apply: Operation not permitted`); it was not used to run tests.
HTTP fixture tests use injected stubs; no live connector QA was performed.

## Manual QA — blocked / not performed

These checks require a separately authorized runtime session with a build from
this exact diff, real MacBook notch hardware, VoiceOver and keyboard access.
Do not install or launch an app as part of this implementation task. Compilation
and unit tests do not establish spoken output, initial focus, focus retention,
AX grouping or physical-notch legibility. Leave every box unchecked until
observed; failures block accessibility acceptance.

Record the tested revision/diff, macOS version, hardware/display scale, keyboard
navigation and VoiceOver settings, reviewer, date, and observed speech/focus.
Use synthetic local demo data, with all optional external sources off. Do not
connect private Pixel HQ data, change permissions, or act on real approvals.

- [ ] **Compact announcement:** reach `companion.notch.statusButton` using
  VoiceOver without pointer hover. Hear one button with status, no duplicate
  character name or SF Symbol name. For current synthetic data, verify no count
  at zero, “1 pending approval” at one, and plural at multiple approvals.
- [ ] **Freshness:** with cached synthetic working activity and approvals,
  exercise connecting, stale and unavailable states. Hear Connecting, Updates
  delayed and Disconnected respectively, without an old working mood or count.
  Verify the expanded summary's visible status agrees and retains provenance.
- [ ] **Activation and entry focus:** use VO-Space on compact and hover-snapshot
  status buttons to open pinned details. Exercise the snapshot's named action
  “Open companion details”. Confirm each opens details once, the content is
  reachable, and no pointer movement is required. Record where focus lands;
  no programmatic initial-focus or focus-restoration behavior is claimed here.
- [ ] **Expanded traversal:** navigate forward/backward from status through
  summary, tabs, selected content and footer in visual order. Confirm status
  comes first, headings appear in the rotor with natural-case names, and no
  group swallows approvals, controls or text. Check every existing detail tab,
  selection announcement, Command-1…4 and arrow navigation.
- [ ] **Dismissal and retention:** Escape dismisses pinned details when the
  panel is key. Re-enter details, open Settings, close Settings and return to
  the companion. Record focus retention/restoration, and check that pointer
  exit does not unexpectedly dismiss pinned details or strand VoiceOver focus.
- [ ] **Settings:** locate “Settings categories”; traverse General, Utilities,
  Notifications, then Connections in their existing groups. Verify one category
  name, native selected state and useful destination hint. Use keyboard sidebar
  selection and pane traversal to reach the matching heading, description and
  named form. Every existing setting remains reachable; labels must not hide
  form children or steal focus on selection. Do not toggle permissions/startup.
- [ ] **Keyboard only:** with macOS Keyboard Navigation enabled, verify visible
  focus, forward/reverse Tab order, activation and escape routes on each
  surface and Settings. Accessibility sort priorities alone do not prove Tab
  order. Confirm no focus trap or unintended connector mutation.
- [ ] **Visual accessibility:** inspect compact, snapshot and details on actual
  notch hardware at standard and increased text/display sizes, light/dark,
  Increase Contrast, Reduce Transparency and Reduce Motion. Check status and
  approval legibility, clipping, focus-ring visibility and menu-bar overlap.
  Compare the menu-bar fallback on a non-notch/external display; retain all
  accepted tabs, utilities and diagnostic disclosures.

The existing `scripts/quality/verify_live_accessibility.swift` only checks
popover tab labels/selection; passing it would not satisfy these notch,
Settings or spoken-VoiceOver requirements. It was not run against a live app.
This checklist is separate from the frozen hold/review/release records.
