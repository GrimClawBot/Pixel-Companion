# Cumulative Alpha PC-083 — Greptile P1/P2 remediation

This additive follow-up repairs full-stack findings in integration PR #166. It is not a release or a protected-main integration authorization. Keep QA85 installed until a new exact-head QA build is validated.

## Safety corrections
- LocalAgentFeedMonitor, CodexTurnMonitor, and ClaudeHookMonitor now read the owner-selected local file on background utility tasks. One in-flight read per selected source; cancellation and revision/source checks discard late results after disable, disconnect or replacement.
- Original Codex notifier argv must meet the installed dispatcher's exact contract before any provider config write: 1–32 nonempty arguments, each at most 4096 characters, executable an absolute path, and JSON-serialized prior command no larger than 16,384 UTF-8 bytes.
- Dry-run and second-provider-write failure tests verify zero dry-run writes, private backups, exact restoration of existing provider configuration bytes and 0600 file permissions.

## Regression verification
- Slow reads and switching sources are exercised through native XCTest for all three monitors. Existing verifier, timeline and rendered UI tests now wait for asynchronous completion; mutable test fixture buffers are protected by locks.
- No real Codex or Claude config, existing hook, production Paperclip/Pixel HQ service, nor actual macOS Login Items are changed by these tests.

## Governance
This is a stacked draft repair. Protected main, source snapshot #166 and public release remain blocked until exact repair-head native CI, Greptile review, independent human GitHub approval, owner UI acceptance and explicit controlled integration authorization. No accepted features may be removed.
