# PC-070 — Verified task and run evidence drilldown

## User-facing flow

From Activity → Company tasks, selecting a task opens a **read-only** task
detail. It shows reported status, current verified assignee if available, and
up to eight recent bounded run records whose **structured**
`contextSnapshot.issueId` matches that exact task ID. Selecting one of these
runs shows run status, reported agent, reported model/provider, timestamps
when present, reported tokens and an explicit "Logs unavailable" explanation.

An adjacent person shortcut preserves the previous direct route from an
assigned task row to the existing agent inspector. Task detail also links to
the current verified assignee. It must NOT represent that current assignment
as evidence that this agent executed earlier runs: an old run can be linked
to the same task through its separately reported run/issue association, even
if its agent differs.

## Boundaries

- `AgentRunSnapshot.issueID` is obtained only from
  `PaperclipHeartbeatRunResponse.contextSnapshot.issueId`. Never infer from
  task title, matching text, current assignee, `taskId` or role.
- A run whose issue ID is not in the current task sample retains its source
  ID but has no invented title or linked current task.
- Only recent bounded run evidence already in the **current, live agent
  telemetry** is displayed. A fresh company-task feed with stale agent
  telemetry shows task metadata but **no historical run links**.
- Real organizational department identifiers and redacted logs do not yet
  exist in the connector snapshot. Do not label role as department, imply a
  complete run audit history, or expose raw server logs.
- No new endpoints, credentials, persisted task history, Paperclip writes,
  agent commands, approvals or chat actions.

## Native regression and acceptance

- Source mapping tests assert explicit issue-ID preservation, including an
  ID outside the bounded issue sample, and reject title-like `taskId` as a
  substitute for `issueId`.
- Pure presentation tests assert exact ID links, historical-vs-current agent
  distinction, stale feed fail-closed, sorted actual reported timestamps,
  duplicate suppression and unassigned task history.
- Real Mac: verify Activity → task → linked run → back, direct agent
  shortcut, missing/no-agent/no-run/long text, narrow 360pt/440pt layout,
  keyboard and VoiceOver, remote feed expiration and a task removed during
  navigation. Inspect no secret/log leakage.
- GitHub CI, Greptile exact SHA, independent human GitHub review and
  owner-controlled integration remain distinct gates. Installed QA61 and
  protected main remain untouched while the PC-070 draft is reviewed.
