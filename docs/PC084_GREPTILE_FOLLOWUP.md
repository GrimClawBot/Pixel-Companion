# PC-084 follow-up: verifier selection and transaction rollback

This patch addresses P1/P2 findings from the Greptile reviews of draft PRs #171 and #172, without modifying any production provider settings.

## Verification source changes

During a pending baseline read, selecting a different folder invalidates its pending completion callback with nil. The verifier exits Waiting and shows Needs Setup rather than timing out indefinitely. Explicit Stop still cancels silently. Already-armed verification is also invalidated when the selected source changes, so new-folder markers cannot count as delivery from an old folder.

Both Codex and Claude implementations are covered by controlled blocked-read and armed-check regression tests.

## Provider rollback failure isolation

Provider rollback is best-effort and does not overwrite detected external edits. Each provider file has independent exception handling, so a missing or concurrently changed Claude config cannot prevent restoration of unchanged Codex bytes. The original installation exception is preserved. Comments no longer assert that a non-existent installer lock is held.

Regression tests remove Claude during final validation and simulate external edits during rollback.

This is not an atomic filesystem compare-and-swap for noncooperating provider processes. Live installation requires separate user authorization. Protected main, QA86, public releases and all real account configuration remain unchanged, pending exact-head native CI, Greptile, independent human review and owner acceptance.
