# Pixel Companion design system (PC-085 Phase 0 draft)

Status: **draft for owner review**. This document describes direction only. It does not authorize any
production view changes (Phases 1–6 are gated on owner approval of Phase 0).

Aesthetic: **Quiet instrument, living character.** The surfaces read like a calm native Mac instrument
panel. The pixel character supplies all of the personality. Chrome never competes with it.

## 1. Invariants (LOCKED)

- The notch plate stays **pure black** (`Color.black`), with bottom-only continuous corners (currently 14 pt).
  It is never tinted, blurred or themed.
- The **original pixel sprite** (`CharacterSprite`, `CharacterView`) is rendered crisp, at integer pixel sizes
  only (no interpolation, no anti-aliased scaling, no redraw of the art).
- No accepted feature is removed. No settings key, `@AppStorage` key or accessibility identifier is renamed.
  Identifiers listed in `docs/PC085_PHASE0_QA_MATRIX.md` are a compatibility contract.
- **No false healthy state.** A source that is connecting, stale, unavailable or unverified must never look like
  `current`. Visual treatment follows `FeedFreshness` and `canPresentAsLive`, never optimistic defaults.
- Pixel HQ / Paperclip connectors stay optional and off by default. The standalone app must look complete
  with no connector.

## 2. Spacing: 4 pt grid

| Token | Value | Use |
|---|---|---|
| `space.0.5` | 2 | icon–label hairline gaps, badge internal vertical |
| `space.1` | 4 | tab bar inset, tight stacks |
| `space.1.5` | 6 | compact notch bar item spacing (existing) |
| `space.2` | 8 | row internal spacing, notch top inset |
| `space.3` | 12 | card padding (existing `companionCard`), header spacing |
| `space.4` | 16 | surface edge padding (notch/popover) |
| `space.5` | 20 | Settings form group spacing |
| `space.6` | 24 | section separation in detail scroll views |

Rules: use only these values in new code. Existing odd values (`HStack(spacing: 3)` in `CompanionTabBar`) become
`space.1` in Phase 1. Tokens are introduced as a `CompanionSpacing` enum next to `CompanionMotion`, adding no
new dependency.

Radii: notch plate 14, card 12 (currently 13, so align to 12 in Phase 1), tab selection 8, badge = capsule.
Always use `.continuous`.

## 3. Typography

System font only (SF Pro and SF Mono through semantic text styles), so Dynamic Type and the user's
Accessibility text size apply.

| Role | Style | Notes |
|---|---|---|
| Surface title / mood | `.headline` | `SummaryHeader` mood title |
| Section title | `.subheadline.weight(.semibold)` | `SectionTitle` |
| Body / row primary | `.callout` | |
| Row secondary, provenance | `.caption` + `.secondary` | always show source and age |
| Numeric (counts, timers, %) | `.monospacedDigit()` | approval badge, focus timer, usage |
| Compact notch status | `.caption.weight(.semibold)`, rounded design | replaces fixed `size: 12` |
| Tab label | `.caption2` | replaces fixed `size: 10` |

Rules: no fixed `.system(size:)` in new code except in the notch compact bar, which has a physical height cap.
That bar must still truncate gracefully at the largest text size. Never put meaning in weight alone.

## 4. Color and materials

Use only native semantic colors: `.primary`, `.secondary`, `.tertiary`, `Color.accentColor`,
`NSColor.controlBackgroundColor`, `.windowBackgroundColor`, `.separatorColor`. Materials: `.regularMaterial` only
on the menu-bar popover background, and only when `accessibilityReduceTransparency` is off. Otherwise use an opaque
`windowBackgroundColor`. The notch interior stays black, and content on it uses `.white` and `.white.opacity(0.6)`.

### Status palette (single source of truth)

| Status | Tint | SF Symbol | Text (always shown, never color-only) |
|---|---|---|---|
| Connected / current | `.green` | `checkmark.circle.fill` | "Live · <age>" |
| Connecting | `.secondary` | `arrow.triangle.2.circlepath` | "Connecting…" |
| Stale | `.yellow` | `clock.badge.exclamationmark` | "Stale · last <age>" |
| Unavailable / offline | `.secondary` | `bolt.horizontal.circle` | "Unavailable" |
| Needs approval | `.orange` | `hand.raised.fill` | "<n> approvals" |
| Error | `.red` | `exclamationmark.triangle.fill` | concise reason |
| Security alert | `.red` | `lock.trianglebadge.exclamationmark` | concise reason |
| Not configured / off | `.tertiary` | `circle.dashed` | "Off" |

Green appears **only** for `FeedFreshness.current` (or a verified local observation). Stale content is dimmed to
`.secondary` and labelled with its age. It is never hidden and never shown as live.

## 5. SF Symbols

- Rendering mode is `.hierarchical`, with `.palette` used only for status pairs. The weight matches adjacent text.
- Tabs: Overview `square.grid.2x2`, Agents `person.2`, Usage `chart.bar`, Activity `clock.arrow.circlepath`.
  These are kept as they are.
- Settings sidebar: General `gearshape`, Connections/Sources `point.3.connected.trianglepath.dotted`,
  Utilities `square.grid.2x2`, Notifications `bell`, Agents `person.2.badge.gearshape`,
  Advanced `slider.horizontal.3`. Agents and Advanced are new **presentation** groupings. They move no keys.

## 6. Shared components (Phase 1 targets)

- `StatusPill(status:)`: icon + text + tint from the table above. Used everywhere a freshness or connection state
  appears.
- `EmptyState(symbol:title:message:action:)`: a neutral, single optional action. Never implies health.
- `ErrorState(reason:recovery:)`: a red symbol with a plain-language reason. Recovery is a button only when the
  action is local and safe.
- `ProvenanceFooter(source:age:)`: every live datum names its source and age.
- `companionCard()`: kept, with radius 12 and padding `space.3`.

## 7. Interactive affordances

- Hit targets are at least 24×24 pt in the notch and 28 pt rows in the popover/detail. `contentShape` covers the full row.
- Hover gets a subtle `Color.primary.opacity(0.05)` fill. Selection gets `accentColor.opacity(0.14)` (existing).
- Every control has a visible keyboard focus ring. Tabs keep ⌘1–⌘4 and the ←/→ move command (existing).
- Destructive or connector-changing actions (disconnect, clear) use `.role(.destructive)` and confirm.

## 8. Motion and character energy

- Durations: micro feedback 0.12 s, tab/section change 0.18 s (existing `CompanionMotion`), notch expand/collapse
  0.24 s with spring `response 0.3, damping 0.85`.
- **Reduce Motion:** all of these become `nil` (instant), and the character holds its first frame of the mood
  loop instead of animating. The character never disappears.
- Character energy maps to mood: idle has a slow blink (≥4 s), working/coding/testing a steady loop,
  thinking a slow loop, waitingForApproval a gentle attention bob (no flashing), error/securityAlert/
  infrastructureAlert a single shake, then still, success a single celebratory frame sequence, then idle,
  offline still and dimmed.
- Nothing flashes faster than 3 Hz. No looping motion in chrome; only the character loops.
- `Conserve energy` (existing setting) caps character frame rate exactly as today.

## 9. Surfaces (direction only)

1. **Compact notch:** character + one status token (`StatusPill` compact) + approval badge. The single
   accessible element stays `companion.notch.statusButton`.
2. **Glance / expanded:** `SummaryHeader` with mood, freshness and last sync, then approvals, then current task.
   Diagnostics collapse behind a disclosure.
3. **Overview:** hierarchy runs Attention (approvals, errors) → Now (active agents, current task) → Health
   (sources, freshness) → Utilities.
4. **Tabs:** keep the 4 tabs. Labels use `.caption2`, and selection uses the existing tint.
5. **Menu-bar fallback:** same content as the notch detail, using the popover material rules above. Used when no
   notch is present.
6. **Settings:** native sidebar with General, Agents, Sources (current "Connections"), Utilities,
   Notifications and Advanced. Grouping is presentation-only. Every existing key and identifier is preserved.
