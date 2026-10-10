#!/usr/bin/env python3
"""Preserve the user's existing Codex notify handler and add Pixel Companion.

Codex appends ONE potentially private JSON arg. Never log, print, or persist
that argument. The prior handler receives the same argv value it did before.
The only Pixel output is the existing scrubbed event + UTC timestamp marker.

This dispatcher MUST be installed only with explicit owner approval, a
private 0600 backup and a verifiably preserved original command.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import stat
import subprocess

if __package__:
    from .codex_notify_bridge import scrub_notification, write_marker
else:
    from codex_notify_bridge import scrub_notification, write_marker

MAX_ARG_BYTES = 262_144
MAX_ORIGINAL_COMMAND_BYTES = 16_384
MAX_ORIGINAL_ARGS = 32


def load_previous_command(path: Path) -> list[str] | None:
    try:
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode):
            return None
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
            return None
        if info.st_size <= 0 or info.st_size > MAX_ORIGINAL_COMMAND_BYTES:
            return None
        obj = json.loads(path.read_bytes())
    except (OSError, ValueError, UnicodeDecodeError):
        return None
    if (
        not isinstance(obj, list) or not (1 <= len(obj) <= MAX_ORIGINAL_ARGS)
        or not all(isinstance(v, str) and 0 < len(v) <= 4096 for v in obj)
        or not Path(obj[0]).is_absolute()
    ):
        return None
    return obj


def dispatch(
    prior: list[str] | None,
    raw: str,
    directory: Path,
    *,
    executor=subprocess.run,
) -> tuple[bool, bool]:
    """Independent bounded delegation; never print the raw event."""
    if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_ARG_BYTES:
        return False, False
    previous_called = False
    if prior is not None:
        try:
            result = executor(prior + [raw], timeout=30, check=False)
            previous_called = result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            pass

    # Codex cannot be broken by a Pixel marker failure. The original
    # handler has already been tried with the exact same raw argument.
    from datetime import datetime, timezone
    current = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    minimal = scrub_notification(raw, current)
    pixel_written = False
    if minimal is not None:
        try:
            write_marker(directory, minimal)
            pixel_written = True
        except (OSError, ValueError):
            pass
    return previous_called, pixel_written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-command-file", required=True, type=Path)
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("event_json")
    args = parser.parse_args()
    prior = load_previous_command(args.original_command_file)
    if prior is None:
        # Fail closed: never silently replace a broken original integration
        # with Pixel Companion. Do not dump path/contents to stderr.
        return 0
    dispatch(prior, args.event_json, args.directory)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
