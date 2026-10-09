# PC-084 — Full-stack review blocker remediation (QA86)

## Scope

This additive stacked patch addresses cumulative Alpha Greptile findings from
PR #166 (not visible in the small PC-083 review on PR #165).

1. LocalAgentFeedMonitor, CodexTurnMonitor and ClaudeHookMonitor now read
   explicitly selected local report files on background utility tasks, never
   on the main actor. They suppress overlapping polls; source changes,
   disabling and disconnecting advance a generation and cancel old tasks.
   No late result can replace the new report. Native XCTest covers blocked
   old-file reads and switches for each monitor.
2. The Codex hook installer validates exactly the notifier bounds its
   installed dispatcher accepts: 1–32 nonempty arguments, at most 4,096
   characters each, absolute executable and serialized JSON no larger than
   16,384 bytes. Invalid input is refused before provider mutation.
3. Isolated Python tests exercise dry-run with no writes, private 0600
   backups, exact original bytes, notifier dispatcher compatibility,
   changed-provider rejection, and restoration after a simulated second
   provider write failure. Real user provider configuration is never opened
   or modified in these tests.

All sources remain read-only and off by default, and no arbitrary commands,
SSH, credentials, protected-main commits or macOS Login Items are changed.

## Isolated QA preview

After current-head native CI passes, build a separate QA86 copy from an
immutable clean checkout using scripts/qa_preview_macos.sh --qa-number 86
--no-open. Verify source SHA, bundle identity, QA marker, code signature and
successful process start before moving only the verified stopped QA85 bundle
to recoverable Trash. Do not replace current settings, delete source
checkouts, or alter provider configuration.

Remaining separate gates: Greptile exact-head P1/P2 review, real human
VoiceOver/keyboard/360pt/440pt visual testing, independent GitHub APPROVED
and explicit protected-main owner integration permission. No public release.

## Second Greptile pass: asynchronous delivery verification boundary

PR #167 identified a further P1 risk: asynchronous source reads meant
AgentHookVerifier could arm before the baseline refresh had completed.
The verification flow now awaits a fresh completed bounded source read
before arming, treats all markers observed during that read as baseline,
and invalidates pending arm tasks when stopped or retried. A marker
already present at the arm boundary cannot be credited as new delivery.
Two new native tests block initial Codex/Claude reads until after Start
Check and prove no premature success, while later genuine markers pass.

Existing verifier negative tests now await actual file delivery before
asserting stale, repeated, timeout, or post-stop suppression. Provider
tests cover accepted exact 32-argument, 4096-character and 16384-byte
serialized command boundaries, along with strictly rejected values
above those bounds. No real provider notification settings were changed.

QA86 is an earlier preview of the same milestone; the new review head
is allocated the isolated QA87 marker and must be built only after
exact-head native CI and package safety gates. The old running preview
remains until a verified replacement is available.
