#!/usr/bin/env python3
"""Dependency-free secret scanner for the Pixel-Companion quality gate.

Scans every tracked file (default) or only the lines added in a git range
(--range BASE..HEAD). Exits 1 when a finding is reported, 0 when clean.

A line can be allowlisted with an inline `quality:allow-secret` marker; every
use of the marker is itself a review item for Greptile and the human reviewer.
"""
from __future__ import annotations

import argparse
import fnmatch
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ALLOW_MARKER = "quality:allow-secret"

CONTENT_RULES: list[tuple[str, re.Pattern[str]]] = [
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----")),
    ("aws-access-key-id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("github-token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})\b")),
    ("slack-token", re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}\b")),
    ("anthropic-key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}\b")),
    ("openai-key", re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}\b")),
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("stripe-live-key", re.compile(r"\b[rs]k_live_[0-9A-Za-z]{20,}\b")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b")),
    (
        "generic-assignment",
        re.compile(
            r"""(?i)\b(?:api[_-]?key|secret|client[_-]?secret|access[_-]?token|auth[_-]?token|password|passwd)\b"""
            r"""\s*[:=]\s*["'][^"'\s$<>{}]{16,}["']"""
        ),
    ),
]

# Files that must never be committed regardless of content.
FORBIDDEN_PATHS = [
    ".env",
    "*/.env",
    ".env.*",
    "*/.env.*",
    "*.p12",
    "*.pfx",
    "*.mobileprovision",
    "*.provisionprofile",
    "*.keychain",
    "*.keychain-db",
    "id_rsa",
    "*/id_rsa",
    "id_ed25519",
    "*/id_ed25519",
    "*.pem",
]
FORBIDDEN_PATH_EXCEPTIONS = [".env.example", "*/.env.example"]


@dataclass(frozen=True)
class Finding:
    rule: str
    path: str
    line: int

    def render(self) -> str:
        # Never echo the matched value: the report itself must not leak it.
        return f"{self.path}:{self.line}: {self.rule}"


def scan_line(path: str, lineno: int, text: str) -> list[Finding]:
    if ALLOW_MARKER in text:
        return []
    return [Finding(rule, path, lineno) for rule, pattern in CONTENT_RULES if pattern.search(text)]


def forbidden_path(path: str) -> bool:
    if any(fnmatch.fnmatch(path, p) for p in FORBIDDEN_PATH_EXCEPTIONS):
        return False
    return any(fnmatch.fnmatch(path, p) for p in FORBIDDEN_PATHS)


def scan_text(path: str, text: str) -> list[Finding]:
    findings: list[Finding] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        findings.extend(scan_line(path, lineno, line))
    return findings


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout


def scan_tracked(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    for path in git(root, "ls-files", "-z").split("\0"):
        if not path:
            continue
        if forbidden_path(path):
            findings.append(Finding("forbidden-file", path, 0))
            continue
        data = (root / path).read_bytes() if (root / path).is_file() else b""
        encoding = "latin-1" if b"\0" in data[:8192] else "utf-8"
        findings.extend(scan_text(path, data.decode(encoding, errors="replace")))
    return findings


def parse_added_lines(diff: str) -> list[tuple[str, int, str]]:
    """Return (path, new_lineno, text) for each added line of a unified diff."""
    added: list[tuple[str, int, str]] = []
    path = ""
    lineno = 0
    hunk = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
    for line in diff.splitlines():
        if line.startswith("+++ "):
            target = line[4:]
            path = target[2:] if target.startswith("b/") else ""
            continue
        m = hunk.match(line)
        if m:
            lineno = int(m.group(1))
            continue
        if not path or line.startswith("--- "):
            continue
        if line.startswith("+"):
            added.append((path, lineno, line[1:]))
            lineno += 1
        elif line.startswith(" "):
            lineno += 1
    return added


def scan_range(root: Path, rev_range: str) -> list[Finding]:
    findings: list[Finding] = []
    for path in git(root, "diff", "--name-only", "--diff-filter=AMR", rev_range).splitlines():
        if forbidden_path(path):
            findings.append(Finding("forbidden-file", path, 0))
    diff = git(root, "diff", "--unified=0", "--no-color", "--no-ext-diff", rev_range)
    for path, lineno, text in parse_added_lines(diff):
        findings.extend(scan_line(path, lineno, text))
    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--range", dest="rev_range", help="scan only lines added in BASE..HEAD")
    args = parser.parse_args(argv)
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
    findings = scan_range(root, args.rev_range) if args.rev_range else scan_tracked(root)
    for f in findings:
        print(f"secret-scan: {f.render()}", file=sys.stderr)
    if findings:
        print(f"secret-scan: FAIL ({len(findings)} finding(s))", file=sys.stderr)
        return 1
    print("secret-scan: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
