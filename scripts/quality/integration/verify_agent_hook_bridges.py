#!/usr/bin/env python3
"""Run installed Codex/Claude hook BRIDGE executables end-to-end, no model calls.

This deliberately does NOT change any real Codex/Claude configuration, launch
AI runtimes, read transcripts/credentials, or prove provider hook delivery.
A source is accepted as *bridge compatible*, NEVER provider authenticated.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[3]
CODEX_BRIDGE = PROJECT / "scripts" / "codex_notify_bridge.py"
CLAUDE_BRIDGE = PROJECT / "scripts" / "claude_hook_bridge.py"
CODEX_MARKER = "pixel-companion-codex-turn.json"
CLAUDE_MARKER = "pixel-companion-claude-event.json"
ALLOWED_CLAUDE = (
    "SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"
)


def fail(message: str) -> None:
    raise AssertionError(message)


def timestamp(date: str) -> datetime:
    parsed = datetime.fromisoformat(date.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        fail("Missing UTC offset")
    return parsed


def verify_marker(folder: Path, filename: str, expected: str) -> None:
    path = folder / filename
    if not path.is_file() or path.is_symlink():
        fail("Expected a regular, non-symlink marker")
    if stat.S_IMODE(path.stat().st_mode) != 0o600:
        fail("Marker file must be user-only 0600")
    raw = path.read_bytes()
    if len(raw) > 2048:
        fail("Marker exceeded expected maximum")
    marker = json.loads(raw)
    if filename == CODEX_MARKER:
        expected_fields = {"schemaVersion", "event", "lastCompletedAt"}
        time_field = "lastCompletedAt"
    else:
        expected_fields = {"schemaVersion", "event", "observedAt"}
        time_field = "observedAt"
    if set(marker) != expected_fields or marker["schemaVersion"] != 1:
        fail("Unexpected marker field - could include private data")
    if marker["event"] != expected:
        fail("Wrong event")
    age = datetime.now(timezone.utc) - timestamp(marker[time_field])
    if not timedelta(seconds=-5) <= age <= timedelta(seconds=30):
        fail("Marker clock did not match local hook time")
    if b"CANARY-PRIVATE-" in raw:
        fail("Private payload leaked to disk")


def invoke(script: Path, folder: Path, payload: dict, via_stdin: bool) -> None:
    if not script.is_file() or script.is_symlink():
        fail("Expected exact checked-in regular bridge file")
    cmd = [sys.executable, str(script), "--directory", str(folder)]
    raw = json.dumps(payload, separators=(",", ":"))
    if not via_stdin:
        cmd.append(raw)
    process = subprocess.run(
        cmd, input=raw.encode() if via_stdin else None,
        capture_output=True, timeout=15, check=False
    )
    if process.returncode != 0:
        fail("Bridge returned non-zero exit status")
    if process.stdout or process.stderr:
        fail("Bridge printed private hook data or diagnostics")


def verify_codex(folder: Path) -> None:
    payload = {
        "type": "agent-turn-complete",
        "input-messages": ["CANARY-PRIVATE-PROMPT"],
        "last-assistant-message": "CANARY-PRIVATE-RESPONSE",
        "cwd": "CANARY-PRIVATE-WORKSPACE",
        "thread-id": "CANARY-PRIVATE-THREAD",
        "turn-id": "CANARY-PRIVATE-TURN",
    }
    invoke(CODEX_BRIDGE, folder, payload, via_stdin=False)
    verify_marker(folder, CODEX_MARKER, "agent-turn-complete")
    path = folder / CODEX_MARKER
    snapshot = path.read_bytes()
    invoke(CODEX_BRIDGE, folder, {"type": "unrelated-event"}, via_stdin=False)
    if path.read_bytes() != snapshot:
        fail("Unsupported Codex event modified marker")
    # A broken symbolic-link replacement may escape the temporary folder.
    secret = folder / "canary-secret"
    secret.write_text("DO-NOT-OVERWRITE")
    path.unlink()
    path.symlink_to(secret)
    invoke(CODEX_BRIDGE, folder, payload, via_stdin=False)
    verify_marker(folder, CODEX_MARKER, "agent-turn-complete")
    if secret.read_text() != "DO-NOT-OVERWRITE":
        fail("Codex bridge followed a malicious marker symlink")


def verify_claude(folder: Path) -> None:
    for event in ALLOWED_CLAUDE:
        payload = {
            "hook_event_name": event,
            "prompt": "CANARY-PRIVATE-PROMPT",
            "last_assistant_message": "CANARY-PRIVATE-RESPONSE",
            "transcript_path": "CANARY-PRIVATE-TRANSCRIPT",
            "session_id": "CANARY-PRIVATE-SESSION",
            "cwd": "CANARY-PRIVATE-WORKSPACE",
        }
        invoke(CLAUDE_BRIDGE, folder, payload, via_stdin=True)
        verify_marker(folder, CLAUDE_MARKER, event)
    path = folder / CLAUDE_MARKER
    original = path.read_bytes()
    invoke(CLAUDE_BRIDGE, folder, {
        "hook_event_name": "PermissionRequest",
        "tool_input": "CANARY-PRIVATE-PERMISSION",
    }, via_stdin=True)
    if path.read_bytes() != original:
        fail("Unsupported Claude event altered marker")


def run_acceptance() -> dict[str, str]:
    prior = os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(prefix="pixel-companion-acceptance-") as directory:
            root = Path(directory)
            if stat.S_IMODE(root.stat().st_mode) != 0o700:
                fail("Temporary directory not private")
            codex = root / "Codex"
            claude = root / "Claude Code"
            codex.mkdir(mode=0o700)
            claude.mkdir(mode=0o700)
            verify_codex(codex)
            verify_claude(claude)
            return {
                "codex_bridge": "PASS",
                "claude_bridge": "PASS",
                "private_payload_scrubbing": "PASS",
                "restricted_atomic_markers": "PASS",
                "actual_codex_provider_delivery": "NOT_TESTED",
                "actual_claude_provider_delivery": "NOT_TESTED",
            }
    finally:
        os.umask(prior)


if __name__ == "__main__":
    try:
        for key, result in run_acceptance().items():
            print(key + ": " + result)
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as exc:
        # No exception details: paths/payloads may be sensitive.
        print("local_bridge_acceptance: FAIL", file=sys.stderr)
        raise SystemExit(1) from None
