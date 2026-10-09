# Pixel Companion — Frozen specification coverage audit

Audit date: 2026-10-08
Code baseline: QA24, SHA c5d58c054d08017f8b38bd5f103180d7650cbf4d.
This is a requirements audit, not user acceptance or a complete-v1 claim.

## Evidence refresh — October 8, 2026 (supersedes QA24 *current-status* labels below)

The matrices following this section are an **archived QA24 discovery baseline**.
Their `BUILT/PARTIAL/MISSING` judgments describe SHA `c5d58c0` only.
Use this refresh to determine current Alpha implementation, not those old labels.

- Current *installed local QA* at last verified Mac check: **QA61**, built from
  PC-065 SHA `e20b4fa0d46e9156105b3895d12d37f4b8ea9ba5`.
  QA61 does **not** contain later PC-066/PC-067 fixes and **cannot** modify
  Launch at Login because it is deliberately marked as a disposable QA build.
- Latest cumulative *source review candidate*: **draft PR #149**, exact SHA
  `fe6fbc4e69c93d274c1daf23e385d4fc846b6bc7`, including PC-065,
  PC-066 and PC-067. Not merged, deployed, or user-accepted. Its GitHub
  Actions workflow `37877032944` passed **141 Python** and **455 Swift**
  tests, lint, build, config and secret checks. CI proves test results, not
  visual accessibility, actual backend permissions or macOS login behavior.
- For post-QA24 source changes, cite the current code/test paths and the
  relevant accepted-on-Mac test evidence; do not substitute file presence
  for successful live functionality.

| Original contract area | Evidence in current Alpha source | Updated status / still needed |
| --- | --- | --- |
| Native notch, menu-bar fallback, four detail tabs, keyboard | `Sources/PixelCompanion/Notch`, `Views/CompanionTabBar.swift`, presentation and keyboard XCTest | **BUILT / HUMAN QA PENDING**: external monitor, clamshell, VoiceOver, contrast/text scaling and sleep/wake matrix |
| Generic independent public core and read-only Paperclip | `PixelCompanionCore/Connector`, `Paperclip`, MockConnector, `docs/ARCHITECTURE.md` | **BUILT READ-ONLY ALPHA**: additional trusted department/run/log data and authenticated connectors not yet complete |
| Public GitHub workflow/PR status | `App/PublicGitHubMonitor.swift`, `Views/PublicGitHubPulseView.swift` | **BUILT, PUBLIC-ONLY**: no private auth, task-linked PR provenance or full branch drilldown |
| Local Codex/Claude agent presence and notifications | `App/CodexTurnMonitor.swift`, `ClaudeHookMonitor.swift`, local-agent feed/alert tests | **BUILT LOCAL OPT-IN PIECES**: not a complete plugin SDK or all-agent integration; do not infer any remote actions |
| Optional timer, Battery/Power, Calendar, Apple Music | `App/FocusTimerController.swift`, `BatteryPowerMonitor.swift`, `CalendarNextEventMonitor.swift`, `MusicNowPlayingMonitor.swift` and matching tests | **BUILT SOURCE + TESTS**: explicit permissions, off-by-default, native visual and privacy QA pending |
| Optional volume/brightness/download HUD, file shelf, clipboard | `App/OutputVolumeMonitor.swift`, `DisplayBrightnessMonitor.swift`, `DownloadProgressMonitor.swift`, `TransientFileShelf.swift`, `TransientClipboardHistory.swift` and matching views/tests | **BUILT SOURCE + TESTS**: availability depends on OS/provider; behavior and privacy still need real hardware/permission acceptance |
| Canonical activities, source priority, original character | `CompanionLiveActivity.swift`, `CharacterStateMachine.swift`, `CharacterView.swift`, live attention views/tests | **PARTIAL**: full priority vocabulary, normalized event envelope, source-specific animation and transient stack behavior not yet established |
| Token usage, context health and safe recommendations | `Connector/ContextHealth.swift`, `Views/ContextHealthSummaryView.swift`, `AgentUsageDashboard.swift` | **PARTIAL**: reported-only metrics exist; do not call them a complete confidence/velocity/quotas or new-chat handoff engine |
| Company/agent/task/run drilldown and approvals | `Views/CompanyTasksView.swift`, `AgentInspectorView.swift`, `AgentRunHistoryView.swift`, `ActivityTimelineView.swift` | **PARTIAL**: source-verified department hierarchy, redacted logs, trusted links, approval detail and server-authorized mutations remain missing/gated |
| Private Pixel/Atlas chat, infrastructure, account/identity | Connector interface contracts; no authorized private backend action protocol | **MISSING OR SECURITY-GATED**: Keychain/Touch ID/Secure Enclave, authenticated ChatBackend, private host data, approvals and changes require server authority and separate human security review |
| Launch at Login | `Settings/LaunchAtLoginController.swift`, `SettingsViewSections.swift`, **10 fake-ServiceManagement tests** on exact SHA | **IMPLEMENTATION + GREPTILE COMPLETE**: safe pending approval cancellation in PC-065 #144, second-pass Greptile 5/5 no findings; **actual user-controlled installed non-QA macOS registration/cancel/startup acceptance still OPEN (#148)** |
| Packaging and protected integration | `scripts/package_macos.sh`, `quality/install_bundle.py`, `protected_cut_audit.py`, PC-066/#146 + PC-067/#147 | **TESTED DRAFT**: symlink-alias and late-link protection; latest CI passed. PC-067 corrected-head Greptile follow-up not yet confirmed. Protected `main` still needs an independent GitHub human approval and owner-authorized integration |

**How to interpret the milestones:** passing a native test suite is sufficient to
say *implemented and tested*, never to say *installed-release accepted* or
*full-v1 finished*. The cumulative Alpha integration cut is separate from the
remaining whole-v1 feature backlog (#48, #58-#65). Public app/binary distribution
is expressly **deferred** (#17), so notarization/release are not active
requirements for developing or testing the local Alpha. No accepted functionality
may be removed to shorten the build (LOCKED-BUILT). PC-065 real-login acceptance
is tracked independently at #148, and final cumulative review at #149.


## Authoritative sources

- Original shared discussion: https://chatgpt.com/share/6ac0a132-0bc4-83ea-8b7c-29ba7cfeb8dc
- Frozen build contract, original Pixel-HQ PR #139 (head aaf6869): https://github.com/GrimClawBot/Pixel-HQ/pull/139
- Original four documents: docs/pixel-companion/README.md, PRODUCT_SPEC.md, ARCHITECTURE.md, BUILD_PLAN.md in that Pixel-HQ PR.
- Current tested read-only Alpha integration PR #51 plus stacked PR #53 (public GitHub), #55 (Low Power Mode), #57 (reported roles).
- Whole-build tracker: https://github.com/GrimClawBot/Pixel-Companion/issues/48
- Adjacent backend/business chat commitments: https://github.com/GrimClawBot/Pixel-HQ/issues/188

Status definitions: BUILT means source and automated tests exist, not human UX signoff; PARTIAL means working pieces but required behaviors absent; MISSING means no working capability; GATED means deliberately held for security and backend review.

## Frozen build plan traceability

| Source | Contract | Current QA24 status | Open requirement |
| --- | --- | --- | --- |
| Gate 0 | SwiftUI/AppKit shell, MockConnector, CI, tests, lint | BUILT: Mac project, mock, CI and package | Mac QA and release gates (#65) |
| v0.1 | Compact/hover/expanded notch and no-notch fallback | BUILT: native controllers, menu bar | External-display/VoiceOver acceptance (#65) |
| v0.1 | Read-only Paperclip health, agents, tasks, runs, approvals, usage | BUILT: GET-only Paperclip adapter and snapshot | Live backend contract/long-run verification (#64, #65) |
| v0.1 | Canonical event envelope with version, source, event ID, time, priority, entity and optional progress | PARTIAL: snapshots and limited activity mapping | Normalized shared event model (#61) |
| v0.1 | Reconnect/backoff, stale labels, bounded caches, cancellation safety | PARTIAL: freshness and generation guards, coalesced GET, wake refresh | Exponential backoff, reliability tests (#65) |
| v0.1 | Keychain secrets and LocalAuthentication lock | MISSING/GATED: read-only AuthProvider contract only | Real backend identity and local auth (#60) |
| v0.2 | Native new approval/run completion/failure notifications | BUILT: permission-gated, baseline dedup | Human OS Notification Center QA (#65) |
| v0.2 | Task completion, security/infra/budget/CI notices, Focus suppression, notification deep links | PARTIAL: in-app attention signals and CI status; not full native notice policy | Event priority (#61), native Focus/deep links (#65) |
| v0.3 | Authoritative approval details and read-only queue | PARTIAL: queue exists; source/risk/expiry/digest review fields incomplete | Secure approval detail (#60) |
| v0.3 | Review/Deny/Approve, exact refresh, stale/digest check, server decision | GATED: no mutation API; this is deliberate | Human-reviewed auth and server actions (#60) |
| v0.4 | Character states plus motion, transient success, personality disable | PARTIAL: original character, five broad moods, some Reduce Motion | Source-specific states, disable/motion (#61) |
| v0.5 | Search and agent/task/run drilldown with structured IDs | BUILT: search, role grouping, inspector, tasks, bounded recent runs | Real-Mac interaction matrix (#65) |
| v0.5 | Company → department → agent → task → run → redacted logs and source links | PARTIAL: role does NOT mean department; logs/deep links absent | Verified hierarchy and log/deep-link connector (#64) |
| v0.6 | Optional GitHub branch/PR/CI status with source SHA | PARTIAL: public read-only latest runs/open PR preview | Task-to-PR links, SHA, deep links, private auth separately (#64) |
| v0.7 | Paperclip health, VPS/HomeLab CPU/RAM/disk/network/temp/deployment | PARTIAL: Paperclip health, no trusted host metrics | Infrastructure source and privacy (#64) |
| v0.8 | Reported token counts, budget, context used/window | PARTIAL: actual run/provider/model, input/cached/output, monthly budget | Daily/weekly, quota confidence and context engine (#58) |
| v0.8 | ContextHealth exact/provider/estimated/unknown, task drift, compactions, smart new-chat advice | MISSING: current context meter alone is insufficient | Context intelligence (#58) |
| v0.9 | Pixel/Atlas streaming chat, sessions, errors, model/provider, safe tool events | MISSING: read-only chat interface only | ChatBackend and authenticated backend (#59, #60) |
| v0.9 | New Chat + Handoff carrying goals, decisions, tasks, memory, PRs, approvals without old logs | MISSING/GATED: no backend session creation | Backend-authoritative handoff (#58, #59) |
| v1.0 | Settings and macOS startup/battery awareness | PARTIAL: settings, opt-in login (not QA), Low Power Mode and wake | Installed signed OS verification (#65) |
| v1.0 | Onboarding, connector manager, accessibility, updater, crash recovery, privacy/screenshots | PARTIAL/MISSING: docs and settings exist, no release acceptance | Mac polish and release (#65) |
| v1.0 | Developer ID signing/notarization/approved release | GATED: ad-hoc numbered QA app only | Exact-SHA review and Owner authorization (#65) |

## Frozen product and shared-chat details that require dedicated tracking

| Requirement or discussion | Status and gap | Delivery issue |
| --- | --- | --- |
| Notch one dominant status, hover context, click focused action, deep link to full apps | PARTIAL: four functional tabs currently Overview/Agents/Usage/Activity, not the original Pixel/Activity/Context/Approvals. Add routes rather than remove accepted tabs. | #59, #60, #65 |
| Priority order: security > owner approval > infra failure > agent failure > critical work > regular activity > utility > media > idle | PARTIAL: simplified priority engine | #61 |
| Thinking/coding/testing/reviewing/waving/success/security/infra/budget-specific character expressions | PARTIAL: five coarse moods, no complete source-driven set | #61 |
| Canonical Live Activities with real progress, transient collapse, stacked lower-priority states | PARTIAL: basic state and summaries only, no falsely inferred percentages | #61 |
| Session/period spend, context confidence, quota/rate window when actually reported, token velocity only with history | PARTIAL: monthly/current-run fields; no fake daily/weekly/velocity/quotas | #58 |
| Context health recommendations and New Chat + Handoff | MISSING: cannot call a meter a handoff engine | #58, #59 |
| Touch ID/Keychain/Secure Enclave challenge with enrolled private device, short session, YubiKey for root | MISSING/GATED: no pretend cosmetic authentication; server remains final authority | #60 |
| Approval object title/resource/risk/expiry/exact digest and idempotent review/deny/approve | PARTIAL/GATED: read-only approvals until secure backend | #60 |
| Full standalone Claude Code/Codex/Hermes and future local agent connectors, extensions framework | PARTIAL: generic interfaces/Mock/Paperclip, no real local agent adapter or extension host | #63 |
| Optional independently deployed Pixel HQ connector with Atlas, private server, org, infrastructure | PARTIAL: Paperclip read-only via user-configured HTTPS or loopback; no Pixel HQ auth | #59, #60, #64 |
| Generic role/group browsing versus real backend department hierarchy | PARTIAL: By role works, but is never evidence of department ID | #64 |
| Trusted GitHub PR/branch/CI links, provider SHA, task-to-PR association | PARTIAL: public CI preview only | #64 |
| VPS/HomeLab health and deployments; private Tailscale/device access, no public management | MISSING in Companion; network segmentation is Pixel HQ scope | #64; Pixel HQ #188 |
| Now Playing, volume/brightness/battery HUD, next calendar item, timers, download progress | MISSING OPTIONAL: modular native conveniences disabled by default | #62 |
| Screen recording/privacy indicator, Focus-aware notifications | MISSING OPTIONAL: native-permission aware | #62, #65 |
| RAM-only clipboard history with concealed/password exclusion; file shelf as references only; contextual AirDrop | MISSING OPTIONAL: no copying secret clipboard or raw files | #62 |
| Gestures, haptics, camera-side notch indicators, command palette, App Intents/Shortcuts | MISSING/PARTIAL: minimal four-tab keyboard shortcuts work | #65 |
| Lock-screen privacy-safe status, full no-notch/clamshell and screen changes, VoiceOver | MISSING/PARTIAL: menu-bar fallback in source, real hardware tests outstanding | #65 |
| iPhone/Watch consumers of future normalized events | FUTURE DISCUSSION, not frozen Mac v1 blocker | Preserve event compatibility (#61) |
| Separate Pixel Office and Mission Control as deeper investigation surfaces | DESIGN INVARIANT: do not squeeze full dashboard/terminal into notch | #64 |
| Least-privilege GitHub Engineering/Review/Release Apps and Paperclip GitHub triggers | PIXEL HQ concern, not permission to operate from notch | Pixel HQ #188 |
| Paperclip hardening ideas (handoff outbox, lease TTL, recovery, run grants, token ceilings) | PIXEL HQ concern; re-verify upstream before coding | Pixel HQ #188 |
| Roblox game-maker division and Blender procurement | SEPARATE possible Pixel HQ business, not Companion feature | Pixel HQ #188 |
| Jellyfin separate dedicated media app, private-island network | PIXEL HQ/HomeLab design, not Companion media implementation | Pixel HQ #188 |

## Original frozen contract — implementation tickets

- #58: Context intelligence, confidence, smart fresh session and scope-safe handoff contract.
- #59: Streaming chat/sessions and Atlas backend integration, gated on real authentication.
- #60: Keychain/LocalAuthentication/Secure Enclave/device trust/authoritative approval actions.
- #61: Versioned canonical Live Activities, full character priority/state vocabulary and animations.
- #62: Standalone Mac utilities off by default, with explicit permissions and privacy.
- #63: Claude/Codex/local agents and an independently usable safe generic extension SDK.
- #64: Deep task/run/log/PR-branch/SHA/department and private infrastructure integration.
- #65: Onboarding/Focus/keyboard/VoiceOver/Shortcuts/energy reliability/updater/release.
- #48: Whole-v1 master tracker; #188 in Pixel HQ: backend/business ideas separate from macOS app.

## Non-negotiable acceptance constraints

1. LOCKED-BUILT: all accepted functionality through QA24 stays; new capabilities are additive.
2. Standalone public Mac app is useful without Pixel HQ; no private Pixel hosts, secrets, org chart, policies or credentials committed.
3. Mac is a client, not Paperclip/Pixel HQ source of truth. No raw SSH/shell or bypass of server approval policy.
4. No fabricated run progress, quota/context confidence, costs, department IDs, root causes or live state from stale data.
5. Device enrollment/private overlay/Touch ID are not interchangeable; YubiKey/higher-assurance root policy and server-side security delays remain authoritative.
6. Apple-like progressive disclosure: compact = one dominant signal; optional utilities off by default; deeper investigations belong in Pixel Office/Mission Control.
7. Use original assets or appropriately licensed implementation; no reuse of proprietary Coucou/Mochi/AgentPeek/SuperIsland art.
8. Real Mac visual/keyboard/VoiceOver/battery/sleep acceptance, final-SHA Greptile or approved substitute, named human security review, Owner release authorization and notarization remain release gates.

This audit closes **discovery and tracking only**, not the feature completion tickets.
