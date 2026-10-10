# PC-084 — Cancellable hook-verification baselines

A verifier must not be retained by a stalled user-selected file read.
The prior async verifier arm tasks awaited monitor read-task completion. Cancelling
an arm task could not interrupt that awaited filesystem operation and kept the
verifier/monitor alive while the read remained stuck.

Each local Codex and Claude marker monitor now exposes a MainActor-only
completion callback for one fresh baseline snapshot. A verification retry
replaces its pending callback; Stop and Stop All release the callback immediately.
The callback captures the verifier and selected monitor weakly. The monitor
reuses its one existing background read and starts one fresh baseline poll only
after an already-in-flight read completes, preventing retry-driven worker
amplification. Source changes clear pending callbacks.

Important limitation: blocking operating-system filesystem I/O cannot always
be forcibly interrupted. The existing reader may remain occupied until its OS
call returns; the change guarantees that the verifier can be released promptly,
cancelled checks cannot arm later, and retries do not spawn additional workers.

Regression tests use synthetic markers and controlled blocking readers for
both providers, stop-and-release retention, 20 consecutive retry attempts and
disconnect during a pending baseline. Existing marker baseline safety and
normal successful verification remain covered by AgentHookVerificationTests.

No real provider configuration or auth token is read/written, no Login Items
change, and no production service is touched. The owner Mac QA86 remains the
installed preview. This stacked review patch is not merge authorization; all
GitHub CI, Greptile, independent approval, UI and release gates remain open.
