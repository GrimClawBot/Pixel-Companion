# PC-059 — Observed run endings across immediate successor runs

Greptile P1 issue from historical PR #51:
The notification detector only examined the agent's currently selected runID.
When an observed running run A finished and a new run B became selected
before the next poll, the terminal A state was available in recentRuns
but never examined by the detector. No completion/failure notice could
be delivered for that real observed transition.

## Resolution

The notification detector now checks bounded, source-reported recentRuns
for terminal evidence of RUN IDs **previously observed active**. The
existing tracked-runs dictionary supplies both eligibility and idempotency:
- A run the app never saw queued/running cannot generate a historical
  replay notification just because a finished record appears.
- A once-observed run can report its ending as the primary selected run
  or later via recent history, and produces no duplicate notice.
- Completion and failure remain separate, aggregated, static-text notices.
- Disconnect or switching connectors still resets historical evidence.
- The existing per-poll TTL and maximum tracking count remain in force.
- There is no new endpoint, background polling, external traffic, or
  notification permission request; current user opt-in is unchanged.

Moved CompanionNoticeDetector to its own Swift source file after the
logic expansion to preserve SwiftLint strict file length/complexity
checks without suppressing any rule. Product behavior remains available
under the same internal type.

## Verifications

Unit coverage includes run A running -> run B running while A completes
in the recent history, observed queued run -> failed in history, no
replay of never-observed completed/failed history and no duplicate
notices when B finishes. Existing notification, HTTP mapping and user
notification privacy tests continue to run in the full native quality
gate. No provider names, task text or session content are included
in notification title/body.

Greptile's historical Alpha review is code-review input, not
authorization to merge. Current app requires the final QA signature,
head-SHA validation, live Paperclip health recheck and stable launch
before old QA54 removal. Neither code-review bots nor tests substitute
for the independent protected-main approval currently deferred at the
user's request.
