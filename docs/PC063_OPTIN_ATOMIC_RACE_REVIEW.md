# PC-063 — Notification opt-in baseline and concurrent agent evidence

Greptile PC-062 review run 85cc2873-4686-4d38-8780-e2a13f2cadb8
on head 75e1df31b2f1aa462bb6038da5de76d2a739cba4
reported one P1 and one P2 issue.

## Runtime notification opt-in after a cached run has already finished

Enabling automatic notifications used to call
notificationManager.setEnabled(true), then observe an earlier
AppModel.snapshot. A completed run in PaperclipConnector cache could
still be represented as running in that published snapshot while
the connector's onChange callback awaited the main queue. The next
capture would then produce a spurious completion/failure notification
for an event that preceded the user's opt-in.

The setter now invokes AppModel.capture() synchronously while automatic
notifications are still disabled, refreshing and publishing the
atomic, verified latest connector cache evidence. Only then does
the notification manager enable itself and establish a baseline
from that same current snapshot.

App-level XCTest simulates exactly this callback gap: Paperclip
already reports a completed run, AppModel still displays running,
and the user enables notifications. It asserts no historical run
alert is delivered and a subsequent actually observed new run
delivers precisely one completion notification.

No macOS permission prompts or notifications are issued by tests.
The opt-in permission and user preference remain unchanged.

## Real simultaneous read/write atomicity regression

The original PC-062 test observed only sequential cache updates,
which would also pass if separate snapshot and timestamp reads
were mistakenly reintroduced.

A new test publishes over 130 session generations on a background
writer while another thread repeatedly executes capturePresentation().
A lock-protected test ledger records the originating core timestamp
for each synthetic session ID before publication. Every captured
session must match its precise recorded time; the reader must
observe more than one generation and the final state must be
consistent. This directly exercises the lock-coherent snapshot
contract without hitting a real Paperclip service.

The only production app edit is the notification opt-in baseline.
No Paperclip API, authorization, connector egress, external publishing,
GitHub branch protection, or provider settings are modified.

Full Mac native quality, GitHub CI and a new Greptile review of the
exact final head are required. The app is QA-only and the existing
signed QA57 stays running until a QA58 replacement is verified healthy.
No main merge or public release is authorized. AlphaGrimStalker
will not be requested until the owner specifically asks.
