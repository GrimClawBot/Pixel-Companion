# Draft comment for GitHub issue #83 (not posted; needs owner approval)

## PC-085 Phase 0: cohesive UI audit and phased plan

**Direction:** Quiet instrument, living character. The plate stays pure black and the sprite stays crisp. All
chrome is native semantic macOS. The character carries the personality.

### Audit findings (from source at 96adbd5)
1. Typography uses fixed point sizes in the tab bar (10/14 pt) and compact bar (12 pt), so it does not follow the
   user's text size.
2. Spacing is inconsistent (3/6/12/16, plus card radius 13 vs tab radius 9/12), and there is no shared token set.
3. Freshness/status treatment is implemented per-view. There is no shared status pill, empty state or error component.
4. Overview mixes attention, health and utilities without a clear priority order.
5. Settings has 4 sidebar sections. Agents and Advanced controls are spread across Connections/General.
6. Reduce Motion is honoured for tab transitions. Character and notch motion rules are not documented.

### Phase 0 verification status
- The fixture harness ran on the owner's Mac (Xcode 26.6 / Swift 6.3.3) and passed 1/1 with 200 reference PNGs. A
  hash review found 112 unique images, and **all 100 standard vs accessibility3 pairs were pixel-identical**. The
  harness shows the views render. It does not show large-text support, which is consistent with finding 1.
- The first run displayed a wall-clock-relative "Last synced" age. Phase 0B removes it from the fixture
  (`lastSuccessfulSync: nil`) and moves that label to manual QA. The Phase 0B commit still needs a Mac re-run.
- The PNGs are review references, not approved golden images.
- VoiceOver, visual acceptance and every other matrix row are still outstanding. Screens other than `CompactBar` and
  `SummaryHeader` have not been rendered or inspected.

### Phased plan (each phase is a separate draft PR, gated on owner approval)
- **Phase 0 (this):** `docs/DESIGN_SYSTEM.md`, inventory + QA matrix, fixture-only render harness. No production
  change.
- **Phase 1:** tokens (`CompanionSpacing`, typography roles) and shared `StatusPill`/`EmptyState`/`ErrorState`.
  Acceptance: the std/ax3 fixture pairs become hash-distinct with no clipping at 360 pt, and a test-only seam makes
  "Last synced" deterministic. See `docs/PC085_PHASE0_QA_MATRIX.md` §5.
- **Phase 2:** compact notch + glance hierarchy.
- **Phase 3:** Overview hierarchy + tab presentation.
- **Phase 4:** menu-bar fallback parity.
- **Phase 5:** Settings regrouping (General/Agents/Sources/Utilities/Notifications/Advanced; no key changes).
- **Phase 6:** motion/character energy polish + full Mac QA pass.

Invariants across all phases: no feature removal, no key or accessibility-ID renames, no false healthy state, and
connectors stay off by default.
