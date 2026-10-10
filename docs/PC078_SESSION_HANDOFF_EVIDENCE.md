# PC-078 — Source-evidence session handoff *readiness* preview

## Purpose

An agent may be nearing its provider-reported context window limit, yet the
read-only Paperclip connector does **not** supply a trusted transcript, task
objective, decisions, memory summary, approved new-chat backend or a secure
handoff API. This is **not** a generated handoff or a button to create one.
It is a review-only evidence checklist in the existing Agent Inspector.

The new disclosure, *Handoff readiness · review only*, shows source-reported:
- The currently selected verified agent and run state, plus session/run IDs,
  model and provider *only* when the live connector supplied them.
- A provider-reported context fraction and existing ContextHealth warning
  when valid used/window numbers are supplied. Missing or impossible context
  values are explicitly unavailable. **Cumulative tokens are not occupancy.**
- Up to **five** unique tasks from the *current bounded company feed*, each
  linked by the exact structured `assigneeAgentID == session.agentID`.
  A task with no ID, a blank title or a different/no assignee is excluded.
  The list is **not** inferred from run titles or a job role, and a bounded
  truncation is labeled.

It explicitly marks five required pieces of information **not supplied by
this connector for handoff**: objective/outcome, decisions/rationale,
blockers/next steps, approved actions/permissions, and authorized memory
references. The UI does not hallucinate any of them from titles or status.

## Safety and freshness

- A stale/disconnected feed or missing agent identity means **no preview**.
  The Agent Directory already resolves the Inspector only from live source
  state; the preview's own model independently fails closed on stale data.
- Disclosure state is local `@State`; run/freshness changes close it.
  No persistent config, clipboard copying, raw logs, conversation scraping,
  filesystem writes, new endpoints or client-side summary generation.
- There is deliberately **no Copy, Send, New Chat, Handoff or Approval**
  action. The real session/agent backend must own authorization, identity,
  data redaction, generation and any future handoff/new-chat operation.
- Existing context guidance, token usages, assigned tasks, task→run views,
  four tabs, reporting hierarchy, settings, Apple-like notch, and accepted
  features are retained.

## Tests and acceptance

New pure Swift XCTest covers: stale/empty identities; exact agent
assignment; deduplication/limit of five unique source task IDs; malformed
or missing task fields; absent/impossible context numbers even when cumulative
tokens exist; valid context and provider provenance; missing session/run IDs;
and no fabricated decisions/permissions.

Real Mac QA should verify:
1. Agents → select a connected agent → *Handoff readiness · review only*,
   expand and inspect source IDs, current tasks and missing-fields checklist.
2. Distinguish a reported assignment from an agent's run history; switch
   agents, lose the connection or change the latest run; no stale carryover.
3. With no context figures, show "not reported", never infer from token totals.
4. Long task names, narrow 360pt / 440pt layouts, VoiceOver, keyboard focus,
   dark/light and Reduce Motion. Ensure disclosure can collapse and no
   accidental clipboard/OS notification/server action occurs.
5. Confirm zero new Paperclip permissions, raw logs, private user documents,
   startup login changes or new external network requests.

## QA78 — owner-local preview

Quit the currently running QA77 via its **Quit** control first. Keep all
older QA application bundles. In Terminal:

```bash
mkdir -p "$HOME/Developer" &&
git clone --depth 1 --branch pc-078/source-evidence-session-handoff-preview \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA78" &&
bash "$HOME/Developer/Pixel-Companion-QA78/scripts/qa_preview_macos.sh" --qa-number 78
```

This creates a *new*, locally signed
`~/Applications/Pixel Companion QA Update 78.app`. The hardened preview
installer refuses to overwrite any existing or symlinked QA78 destination,
accepts only versions 72, 74, 76, 77 and 78, uses an isolated per-build
Info.plist, verifies ad-hoc signature and `PCQAUpdateNumber=78`, and
disables actual Launch at Login for temporary QA bundles. The optional
`--print-plan` prints the target path without touching files. Existing
QA77/QA76/QA74/QA72/QA61 remain untouched.

These QA apps share a bundle ID and may share existing preferences. Do not
run multiple copies at once or assume isolated private credentials.

Verify General shows **0.1.0 (build 78)** and **QA Update #78**. To roll
back, Quit QA78 in-app then open:

```bash
open -n "$HOME/Applications/Pixel Companion QA Update 77.app"
```

## Gates

Native CI source tests do not establish physical Mac acceptance. The PR
remains DRAFT until independent Greptile technical review, human Mac
accessibility/privacy acceptance and required independent human GitHub
approval. Do not merge protected main or publish binary releases without
explicit owner authorization. There is no remote Mac installation while
the desktop connector quota is exhausted.
