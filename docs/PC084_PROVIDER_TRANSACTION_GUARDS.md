# PC-084 — Protect provider settings during partial installer failure

This additive safety patch to the optional Mac Codex/Claude hook installer
mitigates accidental loss of user/provider edits.

Prior behavior rechecked both configurations once, then replaced Codex followed
by Claude. On a later failure it unconditionally restored both old files,
potentially overwriting edits made by another process while the installer ran.

New behavior:
- Compare actual bytes against the prepared snapshot immediately before each
  individual config write; refuse changed files.
- Track which provider writes this attempt completed.
- On failure, visit those files in reverse order. Restore only when the file
  still matches bytes written by this attempt, and compare again immediately
  before restoring. Never revert an untouched provider file or overwrite a
  detected later edit.
- Keep the prior owner-only backups, original notifier preservation and dry-run
  guarantees. Tests exclusively use temporary synthetic Codex/Claude files,
  injecting edits between provider writes, during an injected second write
  failure, and before postwrite verification.

Limitations: this is best-effort detection, not a true cross-process atomic
compare-and-swap. Noncooperating provider processes can still write between
our final comparison and the atomic rename. Do not assert that arbitrary
concurrent writes are impossible. Provider-specific advisory locks cannot
enforce cooperation from external editors. Full live installation remains
separately user-authorized and not performed by this test or review.

Protected main, QA86, actual provider hooks, system Login Items and public
release are unchanged. Exact-head native CI and Greptile review are required
before merging; the remaining notification baseline P2 is tracked separately.
