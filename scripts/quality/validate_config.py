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
import posixpath
import subprocess
import sys
import xml.etree.ElementTree as ET
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
        elif path.name == "contents.xcworkspacedata":
            ET.parse(path)
    except (ValueError, plistlib.InvalidFileException, UnicodeDecodeError, ET.ParseError) as exc:
        return f"{path}: {exc}"
    return None


def is_xcode_lockfile(path: str) -> bool:
    normalized = path.replace("\\", "/")
    return normalized.endswith("/xcshareddata/swiftpm/Package.resolved") and (
        ".xcodeproj/" in normalized or ".xcworkspace/" in normalized
    )


def xcode_project_lockfiles(root: Path, tracked: set[str], project_rel: str) -> set[str]:
    """Return committed lockfiles that can actually govern one Xcode project."""
    project_dir = project_rel.removesuffix("/project.pbxproj")
    candidates = {
        f"{project_dir}/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    }

    # A standalone workspace may own package resolution for member projects.
    for rel in sorted(tracked):
        if not rel.endswith(".xcworkspace/contents.xcworkspacedata"):
            continue
        if ".xcodeproj/project.xcworkspace/" in rel:
            continue
        workspace_file = root / rel
        if not workspace_file.is_file():
            continue
        workspace_dir = rel.removesuffix("/contents.xcworkspacedata")
        workspace_parent = posixpath.dirname(workspace_dir)
        try:
            workspace_xml = ET.parse(workspace_file).getroot()
        except (ET.ParseError, OSError):
            continue
        for element in workspace_xml.iter():
            location = element.attrib.get("location")
            if not location:
                continue
            kind, sep, value = location.partition(":")
            if not sep or kind not in {"group", "container"}:
                continue
            member = posixpath.normpath(posixpath.join(workspace_parent, value))
            if member == project_dir:
                candidates.add(
                    f"{workspace_dir}/xcshareddata/swiftpm/Package.resolved"
                )

    return candidates & tracked


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

    for project_rel in remote_xcode_projects:
        if not xcode_project_lockfiles(root, tracked, project_rel):
            errors.append(
                f"{project_rel} declares remote Swift packages but no applicable committed "
                "Package.resolved was found"
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
        if (
            path.suffix.lower() in JSON_SUFFIXES | PLIST_SUFFIXES
            or path.name == "contents.xcworkspacedata"
        ) and path.is_file():
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
