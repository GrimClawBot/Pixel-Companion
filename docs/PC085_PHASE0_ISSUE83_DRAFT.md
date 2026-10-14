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

### Phased plan (each phase is a separate draft PR, gated on owner approval)
- **Phase 0 (this):** `docs/DESIGN_SYSTEM.md`, inventory + QA matrix, fixture-only render harness. No production
  change.
- **Phase 1:** tokens (`CompanionSpacing`, typography roles) and shared `StatusPill`/`EmptyState`/`ErrorState`.
- **Phase 2:** compact notch + glance hierarchy.
- **Phase 3:** Overview hierarchy + tab presentation.
- **Phase 4:** menu-bar fallback parity.
- **Phase 5:** Settings regrouping (General/Agents/Sources/Utilities/Notifications/Advanced; no key changes).
- **Phase 6:** motion/character energy polish + full Mac QA pass.

Invariants across all phases: no feature removal, no key or accessibility-ID renames, no false healthy state, and
connectors stay off by default.
