#!/usr/bin/env python3
"""Validate tracked configuration files parse cleanly.

Covers JSON (incl. Package.resolved, greptile.json), property lists
(Info.plist, *.entitlements), and Swift package lockfile contracts. Remote
dependencies declared by root SwiftPM or an Xcode project must have a committed
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


def is_xcode_lockfile(path: str) -> bool:
    normalized = path.replace("\\", "/")
    return normalized.endswith("/xcshareddata/swiftpm/Package.resolved") and (
        ".xcodeproj/" in normalized or ".xcworkspace/" in normalized
    )


def lockfile_errors(root: Path, tracked: set[str]) -> list[str]:
    errors: list[str] = []

    manifest = root / "Package.swift"
    if "Package.swift" in tracked and manifest.is_file():
        text = manifest.read_text(encoding="utf-8")
        if re.search(r"\.package\s*\(\s*url\s*:", text) and "Package.resolved" not in tracked:
            errors.append("Package.swift declares remote dependencies but Package.resolved is not committed")

    remote_xcode_projects: list[str] = []
    for rel in sorted(tracked):
        if not rel.endswith(".xcodeproj/project.pbxproj"):
            continue
        path = root / rel
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if "XCRemoteSwiftPackageReference" in text or re.search(r"\brepositoryURL\s*=", text):
            remote_xcode_projects.append(rel)

    if remote_xcode_projects and not any(is_xcode_lockfile(rel) for rel in tracked):
        errors.append(
            "Xcode project declares remote Swift packages but no committed "
            "xcshareddata/swiftpm/Package.resolved was found"
        )
    return errors


def lockfile_error(root: Path, tracked: set[str] | None = None) -> str | None:
    errors = lockfile_errors(root, tracked or set())
    return errors[0] if errors else None


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
    errors.extend(lockfile_errors(root, tracked_paths))
    for err in errors:
        print(f"config: {err}", file=sys.stderr)
    if errors:
        print(f"config: FAIL ({len(errors)} error(s))", file=sys.stderr)
        return 1
    print(f"config: {checked} file(s) valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
