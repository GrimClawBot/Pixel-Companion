#!/usr/bin/env python3
"""Validate tracked configuration files parse cleanly.

Covers JSON (incl. Package.resolved, greptile.json), property lists
(Info.plist, *.entitlements) and the Swift package lockfile contract:
a Package.swift that declares remote dependencies must ship a committed
Package.resolved. Exits 1 on any failure.
"""
from __future__ import annotations

import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

PLIST_SUFFIXES = {".plist", ".entitlements"}
JSON_SUFFIXES = {".json", ".resolved"}


def validate_file(path: Path) -> str | None:
    """Return an error message, or None when the file is valid."""
    suffix = path.suffix.lower()
    try:
        if suffix in JSON_SUFFIXES:
            json.loads(path.read_text(encoding="utf-8"))
        elif suffix in PLIST_SUFFIXES:
            with path.open("rb") as fh:
                plistlib.load(fh)
    except (ValueError, plistlib.InvalidFileException, UnicodeDecodeError) as exc:
        return f"{path}: {exc}"
    return None


def lockfile_error(root: Path, tracked: set[str] | None = None) -> str | None:
    manifest = root / "Package.swift"
    if not manifest.is_file():
        return None
    if re.search(r"\.package\s*\(\s*url\s*:", manifest.read_text(encoding="utf-8")):
        if tracked is None or "Package.resolved" not in tracked:
            return "Package.swift declares remote dependencies but Package.resolved is not committed"
    return None


def main() -> int:
    root = Path(
        subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True).stdout.strip()
    )
    tracked_output = subprocess.run(["git", "ls-files", "-z"], cwd=root, check=True, capture_output=True, text=True).stdout
    tracked_paths = set(filter(None, tracked_output.split("\0")))
    errors: list[str] = []
    checked = 0
    for rel in tracked_paths:
        path = root / rel
        if path.suffix.lower() in JSON_SUFFIXES | PLIST_SUFFIXES and path.is_file():
            checked += 1
            if (err := validate_file(path)) is not None:
                errors.append(err)
    if (err := lockfile_error(root, tracked_paths)) is not None:
        errors.append(err)
    for err in errors:
        print(f"config: {err}", file=sys.stderr)
    if errors:
        print(f"config: FAIL ({len(errors)} error(s))", file=sys.stderr)
        return 1
    print(f"config: {checked} file(s) valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
