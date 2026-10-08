#!/usr/bin/env python3
"""Optional one-shot status publisher; does not read transcripts or run agents.

No agent hooks are installed: call explicitly or from a separately approved
trusted source of TRUE agent state. Only static labels/status and time are saved.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import stat
import tempfile

SOURCES = {"codex", "claude-code", "hermes", "custom"}
STATES = {"running", "waiting", "idle", "completed", "failed"}
IDENTIFIER = re.compile(r"[A-Za-z0-9_-]{1,80}\Z")
MAX_ROWS = 12


def build_feed(sessions: list[tuple[str, str, str, str]], timestamp: str) -> dict:
    if len(sessions) > MAX_ROWS:
        raise ValueError("Too many sessions")
    rows = []
    seen = set()
    for source, session_id, state, label in sessions:
        if source not in SOURCES or state not in STATES:
            raise ValueError("Unknown source or state")
        if not IDENTIFIER.fullmatch(session_id) or session_id in seen:
            raise ValueError("Invalid or duplicate session ID")
        if not (1 <= len(label.strip()) <= 64):
            raise ValueError("Invalid agent label")
        if any(ord(ch) < 32 or ord(ch) == 127 for ch in label):
            raise ValueError("Control character in label")
        seen.add(session_id)
        rows.append({
            "id": session_id, "source": source, "name": label.strip(),
            "state": state, "updatedAt": timestamp,
        })
    return {"schemaVersion": 1, "sessions": rows}


def publish(destination: Path, payload: dict) -> None:
    """Atomic mode-0600 replacement; never follow a destination symlink."""
    parent = destination.parent
    if not parent.is_dir() or destination.is_dir():
        raise ValueError("Output parent must be a directory")
    data = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    if len(data) > 65_536:
        raise ValueError("Status file would exceed 64 KiB")
    descriptor, temp_name = tempfile.mkstemp(prefix=".local-agent-feed-", suffix=".json", dir=parent)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            os.fchmod(handle.fileno(), stat.S_IRUSR | stat.S_IWUSR)
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, destination)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Explicit local JSON path")
    parser.add_argument(
        "--session", nargs=4, action="append",
        metavar=("SOURCE", "ID", "STATE", "LABEL"), required=True,
        help="Repeat to include Codex, Claude Code, Hermes and custom sources",
    )
    args = parser.parse_args()
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    publish(args.output, build_feed(args.session, timestamp))


if __name__ == "__main__":
    main()
