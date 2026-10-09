# PC-069 — Honest context next steps and local keep-working acknowledgement

## Scope

Alpha's read-only ContextHealth model already calculates healthy, watch,
fresh-session recommended, and strongly recommended states only when the
runtime supplies a valid context-used and context-window pair. PC-069 keeps
that evidence boundary and adds an actionable *explanation*, not a backend
action.

- Healthy / unavailable: no suggestion to create another session.
  Missing, negative, or out-of-bounds context values remain **unavailable**.
- Watch: explain that reported context should be monitored.
- Fresh / strongly fresh: recommend starting a separate session *in the
  connected runtime* **after preserving goals, decisions, and active work**.
  The app does not draft or transmit a handoff.
- Usage and agent-inspector views both show source-labeled confidence and
  context guidance. The inspector previously suppressed context entirely.
- **Keep working for now** acknowledges the current advice only in the local
  SwiftUI view state. It never stores a preference, sends a network request,
  starts a chat, changes a run, or silences global notifications. The
  acknowledgement is keyed by agent ID, run ID, reported used/window and
  recommendation; a different agent/run/measurement shows the advice again.
- The guidance button remains individually accessible in VoiceOver and
  visible in the existing 360pt/440pt native UI layouts when context warrants it.

## Security and honesty

Context occupancy is **not** deduced from cumulative token usage or budget
figures. ContextConfidence is `providerReported` for this particular
Paperclip-backed UI, never claimed `exact`. Compactions, task drift, or tool
volume are not guessed if the connector does not expose them; no increase in
network permissions, privacy scope, file writes or server mutations.

Secure New Chat and Handoff are separate future backend-authorized work
under #58/#59/#60. Do not wire a working action without reviewed identity,
scopes, handoff contract and server authorization.

## QA

1. Synthetic core tests check next-step wording only for watch/fresh/strong
   and no invented hints on healthy or unknown states.
2. Pure app tests check acknowledgement identity separation by agent and
   run, refresh for changed reported context, and no acknowledgement key
   with healthy/unavailable data.
3. Native human visual/VoiceOver QA: read-only Usage and Agent inspector at
   360pt/440pt, long agent labels, missing metrics, fresh/strong warnings,
   click Keep working, switch agents, change underlying reported metrics,
   confirm guidance reappears and no server activity or stored preference.
4. Run full quality gate on Mac, then Greptile final-head technical review;
   no independent GitHub approval or owner release authorization is implied.

This PR is draft and stacked on PC-068. No QA app was installed, protected
`main` merge attempted, real Login Items preference mutated, or public
distribution authorized.
