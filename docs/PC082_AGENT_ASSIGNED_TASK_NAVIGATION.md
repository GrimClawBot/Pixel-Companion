# PC-082 — Verified Agent → Assigned Task → Run navigation

## Function

This additive PC-v1 navigation change connects the existing Agent Inspector's
assigned tasks to the **already implemented** `CompanyTaskEvidenceView` and
its source-verified task→run inspector. It adds no new network requests,
permissions, chat actions, private GitHub credentials or backend writes.

- Only an exact, **unique**, nonempty task source ID with
  `TaskSnapshot.assigneeAgentID == current AgentSessionSnapshot.agentID`
  may open an assigned-task detail while the Paperclip feed is live.
- A task reassigned to another agent, removed from the current bounded feed,
  duplicated by source ID or observed when stale is **not navigable**.
  Matching a title, role or department name is never evidence.
- A selected task is freshly re-resolved against the current assigned list
  each render. Selection resets after live freshness loss, changed source
  assignment, or switching agent identities.
- The task details show the source-reported assignee and only runs with an
  explicit backend issue ID matching the task ID; absent redacted run logs
  remain visibly unavailable.
- Navigation back within the agent reads **Assigned tasks** rather than the
  separate Company's **All tasks**. Both original paths remain intact.
- All existing Pixel character, notch alignment, Settings, reporting tree,
  public GitHub, context guidance, session handoff checklist, and verified
  agent→run detail remain available (LOCKED-BUILT).

## Native regression coverage

`AgentInspectorSelectionTests` now checks: exact current assignee, unique
source task IDs, missing/null IDs, stale feeds, source removal, reassignment,
and agent switching. Existing `CompanyTaskRunTraceTests` cover run issue
links and ensure titles alone do not create them. Mac CI must pass native
Swift XCTest, Python QA plan checks, strict SwiftLint, warnings-as-errors
build, config and secrets gates at the **exact** PR head.

## QA82 owner Mac preview and acceptance

QA81 is kept running until the new QA82 bundle compiles and its local ad-hoc
signature and metadata verify. The build is a separate copy, never overwrites
QA81 or alters macOS startup settings.

1. General should display **0.1.0 (build 82)** and **QA Update #82**.
2. Connect to the Paperclip read-only feed; choose **Agents → an agent →
   Assigned tasks**. Tap an eligible task and inspect structured current
   assignee and any source-linked recent runs. Tap **Assigned tasks** to
   return. Confirm the original Company task list still works.
3. Switch to a different agent, remove/reassign a task, or disconnect the
   feed: no stale previous task detail should stay actionable.
4. Check duplicate/unavailable source task IDs, long titles, VoiceOver,
   keyboard focus and 360pt/440pt layout. No fabricated logs or historical
   tasks beyond the bounded feed. No Paperclip control requests.
5. Inspect public GitHub source labels, compact/expanded notch, four tabs,
   Settings, and external-display fallback for regressions.

Build from an owner Mac source checkout (only after green CI):

```bash
mkdir -p "$HOME/Developer" &&
git clone --depth 1 --branch pc-082/verified-agent-assigned-task-navigation \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA82" &&
bash "$HOME/Developer/Pixel-Companion-QA82/scripts/qa_preview_macos.sh" --qa-number 82
```

The strict allowlist now includes 82; --print-plan is side-effect free.
The installer refuses existing destination/source changes or symlinks,
uses a private build Info.plist, verifies ad-hoc signature/marker, and
never changes real Launch at Login. Do not run QA81 and QA82 simultaneously.

Prior QA81 can be moved to a unique directory inside the user's macOS
Trash only **after** QA82 signs, launches and its exact process has been
verified under the owner's previous cleanup permission. Never empty Trash
or remove source repositories, preferences, Keychain data or other apps.

## Remaining acceptance gates

Greptile exact-head technical review, independent human GitHub APPROVED
review, owner screenshot/VoiceOver acceptance, protected-main merge and
public distribution remain **separate and incomplete**. This is a draft
stacked PR, not a final production build.
