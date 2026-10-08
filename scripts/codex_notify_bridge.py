#!/usr/bin/env python3
"""User-opt-in Codex notify hook: discard all message text and session metadata.

Codex passes one JSON argument; do not add loggers, shell calls or any field
from that JSON to the persisted minimal timestamp marker.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import stat
import tempfile

EVENT_FILENAME = "pixel-companion-codex-turn.json"
MAX_INPUT_BYTES = 262_144


def scrub_notification(raw: str, timestamp: str) -> dict[str, object] | None:
    """Accept the only documented supported event type; ignore all other keys."""
    if len(raw.encode("utf-8")) > MAX_INPUT_BYTES:
        return None
    try:
        event = json.loads(raw)
    except (ValueError, TypeError):
        return None
    if not isinstance(event, dict) or event.get("type") != "agent-turn-complete":
        return None
    return {
        "schemaVersion": 1,
        "event": "agent-turn-complete",
        "lastCompletedAt": timestamp,
    }


def write_marker(directory: Path, marker: dict[str, object]) -> Path:
    """Atomic 0600 write to an existing, explicitly configured local directory."""
    if not directory.is_dir() or directory.is_symlink():
        raise ValueError("Destination must be a real, existing directory")
    destination = directory / EVENT_FILENAME
    serialized = json.dumps(marker, separators=(",", ":")).encode("utf-8")
    if len(serialized) > 2048:
        raise ValueError("Oversized event")
    descriptor, stage = tempfile.mkstemp(prefix=".pc-codex-", dir=directory)
    try:
        with os.fdopen(descriptor, "wb") as writer:
            os.fchmod(writer.fileno(), stat.S_IRUSR | stat.S_IWUSR)
            writer.write(serialized)
            writer.flush()
            os.fsync(writer.fileno())
        os.replace(stage, destination)
    finally:
        if os.path.exists(stage):
            os.unlink(stage)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("event_json", help="JSON argument supplied automatically by Codex")
    args = parser.parse_args()
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    minimal = scrub_notification(args.event_json, timestamp)
    if minimal is None:
        return 0  # Unknown events do not alter previously valid state.
    try:
        write_marker(args.directory, minimal)
    except (OSError, ValueError):
        return 0  # Never disrupt Codex or dump incoming text to stderr/logs.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
