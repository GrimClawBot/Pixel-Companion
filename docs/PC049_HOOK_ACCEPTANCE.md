# PC-049 — Local agent hook acceptance

## Scope and verified results

QA on October 8, 2026, connected Apple Silicon MacBook Pro:
Codex CLI version 0.154.0, Claude Code CLI version 2.1.284,
and Apple Python 3.9.6. Both CLIs were checked using safe version/help
commands; no AI model was asked to generate a response.

This acceptance checks the *real checked-in Python bridge executables*
using their documented invocation interfaces: Codex one JSON argv
argument, Claude Code JSON over stdin. It uses a disposable private
0700 folder and never reads or edits existing Codex/Claude configuration,
credentials, transcripts, or conversations.

To repeat:

    /usr/bin/python3 scripts/quality/integration/verify_agent_hook_bridges.py

Results:

| Check | Result |
| --- | --- |
| Codex bridge launched with JSON argv | PASS |
| Claude bridge launched via JSON stdin for five events | PASS |
| Sensitive canary prompts, answers, paths and IDs discarded | PASS |
| Atomic private 0600 event-only marker | PASS |
| Unknown event does not change marker | PASS |
| Malicious symlink does not redirect bridge write | PASS |
| Actual Codex runtime invoked user-configured notify | NOT TESTED |
| Actual Claude Code runtime invoked user-configured hooks | NOT TESTED |
| Human privacy, VoiceOver and narrow Settings acceptance | NOT TESTED |

The harness prints only aggregate status. It proves bridge executable
compatibility, NOT live provider integration. Another local process with
write access to an event folder could forge a status marker. Neither
a marker change nor a completed turn guarantees task success.

## Real-provider acceptance checklist (user opt-in needed)

1. In Settings > Connections > Guided local agent setup, choose the
   trusted bridge script and a private user-owned event folder.
2. Copy and MANUALLY MERGE the proposed snippet into existing provider
   configuration, preserving any existing notify/hook settings. Codex
   IDE sessions might not invoke Codex CLI notify.
3. Explicitly Connect read-only display in the guide.
4. Press Start check under Verify hook delivery, then MANUALLY run one
   ordinary Codex or Claude Code turn (may consume plan/API usage).
5. Confirm NEW local marker observed, not just an old status file.
   Check the corresponding Agents/Activity event. Investigate timeout
   before claiming successful integration.
6. Test disconnect/disable, stale state, narrow Settings, VoiceOver
   and macOS Focus. Review independently for security/privacy.
7. To stop all external writes, independently remove the hook from
   provider settings and delete its output marker/folder. The app
   OFF toggle does not uninstall external hooks.

PC-049 did NOT install hooks, run actual model turns, or write synthetic
events into the user's configured folders. Disposable acceptance
folders were deleted afterward. Live-provider acceptance and public
release security/visual review remain OPEN.
