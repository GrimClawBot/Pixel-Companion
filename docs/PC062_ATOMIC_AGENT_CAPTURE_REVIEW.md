# PC-062 — Atomic Paperclip agent evidence and AppModel regressions

Greptile review 528399ed-e323-44c3-8c5c-69daa133fe5a of PC-060
identified three P1 issues.

## Atomic data evidence

PC-060 separately read ConnectorSnapshot and successful session time,
allowing a concurrent session update between reads. PaperclipConnector
now provides capturePresentation() as one locked, immutable capture
holding snapshot rows, last successful core time, and successful
session time. AppModel consumes that single capture for both UI
and notification observation. Unverified agent session rows are
cleared BEFORE publishing to the AppModel snapshot, preventing a
view bypass from labeling old rows live.

The capture method is read-only and does not call external providers
or reveal credentials. Mock/disabled connectors keep the generic
ConnectorSnapshot path.

## Fresh core tasks stay visible

CompanyTasksView now receives independently valid core isLive
state, while links to assigned agent profiles use filtered, verified
liveSessions only. Fresh company tasks remain visible even when
agent session telemetry is unavailable.

## Real AppModel regression evidence

Tests instantiate a controlled synthetic PaperclipServiceProtocol,
an injected PaperclipConnector, isolated UserDefaults and a recording
notification center; they never connect to production or prompt macOS.
They verify all 181 agent rows are published, fresh core tasks and
approvals persist without session data, session success/failure
changes visibility, and notifications never observe stale agent rows.
An enabled notification delivers a later observed completion exactly
once; opting out delivers nothing. The connector test verifies
session rows and their timestamps are captured together across
successive refresh publications.

## Boundaries

No Paperclip production, Codex/Claude or Sky notifier setting is
changed. QA56 remains fallback until new exact-SHA local QA passes
full gate, signing, launch and Paperclip health checks. The stacked
PR remains draft; no main merge or public release. Greptile
review is separate from independent GitHub human approval.
AlphaGrimStalker remains unrequested until specifically authorized.
