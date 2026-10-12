# PC-085 — visual refinement and release QA (draft)

This branch starts the approved Pixel Companion UI-completion work on top of the cumulative PC-084 integration review branch. It does not remove accepted functionality, merge stacked feature PRs, publish the app, or replace an installed build.

## Visual acceptance

1. **Compact notch:** character and essential source-verified status fit within the physical notch width; VoiceOver announces the interactive capsule as a single actionable status without reporting stale agent information as live.
2. **Expanded snapshot:** prioritize active status, current task and approvals; collapse advanced runtime diagnostics rather than remove them.
3. **Detail:** group Agents, Activity, Usage, Utilities and Settings into understandable navigation; preserve provenance and stale/unavailable states.
4. **Settings:** use native macOS sidebar grouping, consistent spacing and explicit privacy/connector permissions. Existing approvals remain fail closed.
5. **Visual QA:** compare compact/hover/detail states on real MacBook notch hardware at standard and increased text sizes, dark/light accessibility settings and VoiceOver/reduced-motion.
6. **Integration:** preserve independent public standalone usefulness; Pixel HQ connectors remain optional and off by default.

## Gates

- Compile the exact head and run focused Swift tests before installing preview.
- Confirm accessibility semantics with VoiceOver on the Mac (not infer success from compilation).
- Keep PC-065 real Launch at Login acceptance separate; do not mark it complete from UI work.
- Review cumulative PC-084 stack and avoid merging accepted integration work on visual test results alone.
- No public distribution or production replacement without explicit owner QA acceptance.

Status: **in progress / draft**.
