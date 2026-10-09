#!/usr/bin/env python3
"""Optional Claude Code command hook: accept stdin JSON, emit NO decisions.

Only an allowlisted event name and locally observed UTC time are persisted.
Never copy prompt, cwd, session id, transcript path, error, or tool content.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

EVENT_FILENAME = "pixel-companion-claude-event.json"
MAX_INPUT_BYTES = 262_144
MAX_OUTPUT_BYTES = 2_048
EVENTS = frozenset({
    "SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd",
})


def scrub_notification(payload: bytes, timestamp: str) -> dict[str, object] | None:
    """Discard all fields except a known lifecycle event name."""
    if not payload or len(payload) > MAX_INPUT_BYTES:
        return None
    try:
        data = json.loads(payload)
    except (ValueError, UnicodeDecodeError, TypeError):
        return None
    if not isinstance(data, dict):
        return None
    name = data.get("hook_event_name")
    if not isinstance(name, str) or name not in EVENTS:
        return None
    return {"schemaVersion": 1, "event": name, "observedAt": timestamp}


def write_marker(directory: Path, event: dict[str, object]) -> Path:
    """Write only the fixed marker in a private existing, non-symlink folder."""
    if not directory.is_dir() or directory.is_symlink():
        raise ValueError("Expected an existing real directory")
    encoded = json.dumps(event, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    if len(encoded) > MAX_OUTPUT_BYTES:
        raise ValueError("Oversized event marker")
    descriptor, stage = tempfile.mkstemp(prefix=".pc-claude-", dir=directory)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            os.fchmod(stream.fileno(), stat.S_IRUSR | stat.S_IWUSR)
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(stage, directory / EVENT_FILENAME)
    finally:
        if os.path.exists(stage):
            os.unlink(stage)
    return directory / EVENT_FILENAME


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True, type=Path)
    options = parser.parse_args()
    # Claude Code sends JSON on stdin, NOT argv. Bounded read and no logging.
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    event = scrub_notification(raw, timestamp)
    if event is None:
        return 0
    try:
        write_marker(options.directory, event)
    except (OSError, ValueError):
        # Never emit a permission decision or interfere with Claude.
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
