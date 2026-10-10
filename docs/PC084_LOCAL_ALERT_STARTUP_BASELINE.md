# PC-084 — Suppress historical local notification on app start

The opt-in local Codex/Claude marker monitors now read on background threads.
When settings had already enabled local alerts before an app restart, alert
activation previously baselined only the empty in-memory timeline. A delayed
first marker that was written shortly before launch could then appear as a
new activity banner once macOS notification permission became available.

LocalAgentAttention records the enable timestamp and will never deliver a
marker at or before that instant, regardless of when its asynchronous file
read finally completes. Existing UI activity history remains visible,
and later post-enable milestones still qualify subject to permission and
the existing notification age, cooldown, and deduplication gates.
Source marker timestamps have second precision: events recorded within the
activation second are conservatively suppressed to avoid replay. This is an
intentional safe false negative.

Unit tests cover delayed initial observations inside the otherwise eligible
30-second freshness window and the activation-second boundary. An AppModel
integration test injects a first read held until after permission is ready,
asserts no banner for the existing marker, then delivers a genuinely newer
marker and verifies one local Codex notification through an isolated fake
notification center.

The test modifies no real user prefs, hook files or Notification Center.
A test-only monitor injection point in AppModel defaults to the original
production Codex monitor. QA86 is not updated. This is a stacked draft
pending exact-head native CI, Greptile, human QA and protected release gates.
