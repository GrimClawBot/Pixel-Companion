# PC-060 — Independent agent telemetry freshness and full directory capture

Historical Greptile review of Alpha PR #51 (run
6e704bf0-f146-4c56-b364-21af817f7611) identified two
high-priority session presentation issues. The previously accepted
macOS QA55 could still reproduce the underlying state-flow risks.

## Separate proof of core and session freshness

The connector still refreshes core Paperclip health, company, approvals,
tasks and company costs independently of the slower agent telemetry.
It now tracks the last SUCCESSFUL session telemetry timestamp separately.

A newer core response cannot silently refresh agent sessions or justify
labeling previous run statuses as current. The UI and notch preview
require agent-session freshness before displaying live agent identities,
run status, agent usage or agent-driven activity/attention; while waiting,
they display an explicit agent-telemetry warning rather than labeling
old agent data as verified current. The core status/approval display
remains available when only agent telemetry is delayed.

A session response associated with an older core generation may finish
after newer core polls and still be accepted ONLY if it has the same
selected company and no newer accepted session response. The session's
freshness timestamp derives from its original core publication time,
not delayed callback arrival, preventing arbitrarily late responses
from appearing freshly fetched. A later valid session result supersedes
it. Core failure, company switching and session failure clear session
freshness; older company and older accepted generations cannot refill
it. Outstanding generation metadata is bounded to 32 core generations.

Automatic notification observation excludes agent sessions with missing
or stale session freshness. It does not suppress verified, up-to-date
company approval notifications. Notification opt-in and static
non-sensitive notification text remain unchanged.

## Avoid client-side agent-directory truncation

AppModel captures all agent session rows delivered by the connector for
both the main UI and opted-in notification observation instead of
defaulting to eight rows or the previous separate 128-row limit.
The Overview panel remains visually compact, while the directory,
inspector, search and active/count summaries operate on the full
locally received array. No new Paperclip endpoints or credentials were
added and server pagination is not inferred from this local fix.

## Regression evidence and release gates

Native tests cover:
- Faster repeated core polls with a slower prior session callback
- A newer accepted session blocking an older late callback
- Company switching rejecting previous-company telemetry
- Core health updates not changing session freshness, plus failed
  session completion invalidating previous agent status evidence
- 181 full-directory records and searching agent number 180
- Missing/stale session freshness never inferred from healthy core status

The app's published settings and utility preferences retain the same
interface after a small Swift source split required by strict file
and type-body lint limits. No lint restrictions were reduced.

A source-code update to QA55 requires a fresh production build from
the exact head SHA, verified app metadata/signature, confirmed launch,
and Paperclip loopback health check before QA55 is removed.
No main merge or public release is implied by this local validation.
AlphaGrimStalker remains an unrequested reviewer until explicitly
authorized by the owner; Greptile is the current AI review channel.
