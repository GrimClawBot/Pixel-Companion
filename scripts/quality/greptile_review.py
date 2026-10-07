#!/usr/bin/env python3
"""Agent-friendly Greptile review of committed changes (BASE...HEAD).

Usage:
    scripts/quality/greptile_review.py --base origin/main [--head HEAD] [--out report.json]

Environment:
    GREPTILE_API_KEY   Greptile API key (required)
    GITHUB_TOKEN       GitHub token with read access to the repository (required)
    GREPTILE_REPO      owner/name, defaults to the origin remote
    GREPTILE_BRANCH    indexed branch used for repository context, default "main"

Exit codes (also written as `verdict` in the JSON report):
    0  pass                   no release-blocking findings, no sensitive surface
    1  blocked                release-blocking findings; builder must fix, rerun
                              native checks, then rerun this review
    2  incomplete             missing credentials, dirty tree, oversized diff,
                              API failure or unparseable response; NOT a pass
    3  human_review_required  review is clean but the change touches a
                              sensitive surface; never auto-approve
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass, field
from pathlib import Path

GREPTILE_API = "https://api.greptile.com/v2"
MAX_DIFF_BYTES = 120_000
BLOCKING_SEVERITIES = {"blocker", "major"}
SEVERITIES = ("blocker", "major", "minor", "nit")

EXIT_PASS, EXIT_BLOCKED, EXIT_INCOMPLETE, EXIT_HUMAN = 0, 1, 2, 3

# Paths whose changes always require a human reviewer (auth, secrets, CI,
# infrastructure, dependencies, entitlements/permissions, the gate itself).
SENSITIVE_PATHS: list[tuple[str, str]] = [
    (".github/*", "ci"),
    ("scripts/quality/*", "quality-gate"),
    ("greptile.json", "quality-gate"),
    ("Makefile", "ci"),
    ("*.xcconfig", "build-config"),
    ("*.entitlements", "permissions"),
    ("*Info.plist", "permissions"),
    ("*.pbxproj", "build-config"),
    ("Package.swift", "dependencies"),
    ("Package.resolved", "dependencies"),
    ("*auth*", "auth"),
    ("*login*", "auth"),
    ("*signin*", "auth"),
    ("*session*", "auth"),
    ("*oauth*", "auth"),
    ("*keychain*", "secrets"),
    ("*credential*", "secrets"),
    ("*secret*", "secrets"),
    ("*token*", "auth"),
    ("*/security/*", "security"),
]
PUBLIC_API_PATTERN = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public|open)\s")
PUBLIC_CALLABLE_PATTERN = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public|open)\s+"
    r"(?:override\s+|final\s+|static\s+|class\s+|mutating\s+|nonmutating\s+)*"
    r"(?:func|init|subscript)\b"
)
PUBLIC_TYPE_PATTERN = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public|open)\s+"
    r"(?:final\s+|indirect\s+)*"
    r"(?:class|struct|enum|protocol|actor|extension)\b"
)
SENSITIVE_CONTENT: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\b(?:SecItem\w*|kSecClass\w*|Keychain)\b"), "secrets"),
    (re.compile(r"\b(?:authorization|bearer|api[_-]?key|access[_-]?token|password|passwd|signin|sign_in|login|logout|session|oauth|credential)\b", re.IGNORECASE), "auth"),
    (re.compile(r"quality:allow-secret", re.IGNORECASE), "secrets"),
    (re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b", re.IGNORECASE), "secrets"),
    (re.compile(r"\b(?:NSAppTransportSecurity|NSAllowsArbitraryLoads|com\.apple\.security\.)"), "security"),
]


@dataclass
class Finding:
    severity: str
    file: str
    line: int | None
    title: str
    detail: str = ""

    @property
    def blocking(self) -> bool:
        return self.severity in BLOCKING_SEVERITIES


@dataclass
class Report:
    verdict: str
    base: str
    head: str
    head_sha: str
    findings: list[Finding] = field(default_factory=list)
    sensitive_reasons: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def _public_declaration_end(lines: list[tuple[str, str]], start: int) -> int:
    """Return the last logical line that belongs to a public/open declaration."""
    first = lines[start][1]
    if PUBLIC_CALLABLE_PATTERN.search(first):
        depth = 0
        saw_paren = False
        end = start
        for index in range(start, len(lines)):
            text = lines[index][1]
            depth += text.count("(") - text.count(")")
            saw_paren = saw_paren or "(" in text
            end = index
            if saw_paren and depth > 0:
                continue
            if index + 1 < len(lines):
                nxt = lines[index + 1][1].lstrip()
                if nxt.startswith(("->", "where ", "async ", "throws ", "rethrows ")):
                    continue
            break
        return end

    if PUBLIC_TYPE_PATTERN.search(first):
        end = start
        for index in range(start, len(lines)):
            text = lines[index][1]
            end = index
            if "{" in text:
                break
            stripped = text.rstrip()
            nxt = lines[index + 1][1].lstrip() if index + 1 < len(lines) else ""
            if not (
                stripped.endswith((",", ":", " where"))
                or nxt.startswith(("{", "where ", ","))
            ):
                break
        return end

    return start


def _hunk_changes_public_api(hunk: list[tuple[str, str]]) -> bool:
    """Check old and new logical hunk views for edits inside public API signatures."""
    for changed_prefix in ("+", "-"):
        logical = [
            (prefix, text)
            for prefix, text in hunk
            if prefix == " " or prefix == changed_prefix
        ]
        for index, (prefix, text) in enumerate(logical):
            if not PUBLIC_API_PATTERN.search(text):
                continue
            end = _public_declaration_end(logical, index)
            if any(
                logical[pos][0] == changed_prefix
                for pos in range(index, end + 1)
            ):
                return True
    return False


def classify_sensitive(paths: list[str], diff: str) -> list[str]:
    """Return sorted, de-duplicated reasons a change needs human review."""
    reasons: set[str] = set()
    for path in paths:
        for pattern, reason in SENSITIVE_PATHS:
            if fnmatch.fnmatch(path.lower(), pattern.lower()):
                reasons.add(f"{reason}: {path}")

    current_path = ""
    old_path = ""
    hunk: list[tuple[str, str]] = []

    def flush_hunk() -> None:
        nonlocal hunk
        if current_path.lower().endswith(".swift") and _hunk_changes_public_api(hunk):
            reasons.add("public-api")
        hunk = []

    for line in diff.splitlines():
        if line.startswith("--- "):
            candidate = line[4:]
            old_path = candidate[2:] if candidate.startswith("a/") else ""
            continue
        if line.startswith("+++ "):
            flush_hunk()
            candidate = line[4:]
            current_path = candidate[2:] if candidate.startswith("b/") else old_path
            continue
        if line.startswith("@@"):
            flush_hunk()
            continue
        if not line or line[0] not in " +-":
            continue

        prefix, content = line[0], line[1:]
        hunk.append((prefix, content))
        if prefix in "+-":
            for pattern, reason in SENSITIVE_CONTENT:
                if pattern.search(content):
                    reasons.add(reason)

    flush_hunk()
    return sorted(reasons)


def parse_findings(message: str) -> list[Finding]:
    """Extract the JSON findings array from Greptile's answer.

    Raises ValueError when no well-formed array is present: an unparseable
    review is never treated as clean.
    """
    fenced = re.search(r"```(?:json)?\s*(\[.*?\])\s*```", message, re.DOTALL)
    candidate = fenced.group(1) if fenced else message[message.find("[") : message.rfind("]") + 1]
    if not candidate:
        raise ValueError("no JSON findings array in Greptile response")
    raw = json.loads(candidate)
    if not isinstance(raw, list):
        raise ValueError("Greptile findings payload is not a list")
    findings = []
    for item in raw:
        if not isinstance(item, dict):
            raise ValueError(f"Greptile finding is not an object: {item!r}")
        severity = str(item.get("severity", "")).lower()
        if severity not in SEVERITIES:
            # Unknown severities are escalated, not ignored.
            severity = "blocker"
        line = item.get("line")
        findings.append(
            Finding(
                severity=severity,
                file=str(item.get("file", "")),
                line=int(line) if isinstance(line, (int, str)) and str(line).isdigit() else None,
                title=str(item.get("title", "")).strip() or "(untitled)",
                detail=str(item.get("detail", "")).strip(),
            )
        )
    return findings


def decide(findings: list[Finding], sensitive_reasons: list[str]) -> tuple[str, int]:
    if any(f.blocking for f in findings):
        return "blocked", EXIT_BLOCKED
    if sensitive_reasons:
        return "human_review_required", EXIT_HUMAN
    return "pass", EXIT_PASS


def build_prompt(repo: str, base: str, head_sha: str, diff: str) -> str:
    return (
        f"You are the independent release reviewer for {repo}, a native macOS (Swift/SwiftUI/AppKit) "
        f"notch companion app. Review ONLY the committed diff below ({base}...{head_sha}) using the "
        "indexed repository for context. Look for correctness bugs, crashes, concurrency/main-thread "
        "violations, memory leaks/retain cycles, security and privacy problems, secret exposure, "
        "missing or inadequate tests, and broken public API contracts.\n\n"
        "Severity scale:\n"
        "- blocker: must not ship (crash, data loss, security/secret issue, broken build/test)\n"
        "- major: significant defect or missing test coverage for changed behaviour\n"
        "- minor: real but low-impact issue\n"
        "- nit: style or naming\n\n"
        "Respond with ONLY a JSON array inside a ```json fenced block. Each element: "
        '{"severity": "blocker|major|minor|nit", "file": "path", "line": 123, '
        '"title": "short summary", "detail": "why it is wrong and how to fix"}. '
        "Respond with ```json\n[]\n``` when there are no findings.\n\n"
        f"```diff\n{diff}\n```"
    )


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def origin_repo() -> str:
    url = git("remote", "get-url", "origin").strip()
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$", url)
    if not m:
        raise ValueError(f"cannot derive owner/repo from origin {url!r}; set GREPTILE_REPO")
    return m.group(1)


def greptile_post(path: str, body: dict, api_key: str, github_token: str) -> dict:
    req = urllib.request.Request(
        f"{GREPTILE_API}{path}",
        data=json.dumps(body).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "X-GitHub-Token": github_token,
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=600) as resp:
        return json.loads(resp.read().decode())


def run_review(args: argparse.Namespace) -> Report:
    head_sha = git("rev-parse", args.head).strip()
    report = Report(verdict="incomplete", base=args.base, head=args.head, head_sha=head_sha)

    if git("status", "--porcelain", "--untracked-files=no").strip() and not args.allow_dirty:
        report.notes.append("working tree has uncommitted changes; commit before review")
        return report

    rev_range = f"{args.base}...{head_sha}"
    paths = git("diff", "--name-only", rev_range).splitlines()
    diff = git("diff", "--no-color", "--no-ext-diff", rev_range)
    report.sensitive_reasons = classify_sensitive(paths, diff)
    if not diff.strip():
        report.notes.append("empty diff; nothing to review")
        return report
    if len(diff.encode()) > MAX_DIFF_BYTES:
        report.notes.append(f"diff exceeds {MAX_DIFF_BYTES} bytes; split the change into smaller PRs")
        return report

    api_key = os.environ.get("GREPTILE_API_KEY", "")
    github_token = os.environ.get("GITHUB_TOKEN", "")
    if not api_key or not github_token:
        report.notes.append("GREPTILE_API_KEY and GITHUB_TOKEN must both be set")
        return report

    repo = os.environ.get("GREPTILE_REPO") or origin_repo()
    branch = os.environ.get("GREPTILE_BRANCH", "main")
    target = {"remote": "github", "repository": repo, "branch": branch}
    try:
        # Idempotent: (re)indexes the context branch; no-op when already indexed.
        greptile_post("/repositories", {**target, "reload": False, "notify": False}, api_key, github_token)
        answer = greptile_post(
            "/query",
            {
                "messages": [{"id": "review", "role": "user", "content": build_prompt(repo, args.base, head_sha, diff)}],
                "repositories": [target],
                "genius": True,
                "stream": False,
            },
            api_key,
            github_token,
        )
        report.findings = parse_findings(str(answer.get("message", "")))
    except (urllib.error.URLError, ValueError, json.JSONDecodeError) as exc:
        report.notes.append(f"greptile request failed: {exc}")
        return report

    report.verdict, _ = decide(report.findings, report.sensitive_reasons)
    return report


EXIT_FOR_VERDICT = {
    "pass": EXIT_PASS,
    "blocked": EXIT_BLOCKED,
    "incomplete": EXIT_INCOMPLETE,
    "human_review_required": EXIT_HUMAN,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", required=True, help="base ref, e.g. origin/main")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--out", help="write the JSON report to this path")
    parser.add_argument("--allow-dirty", action="store_true", help="review committed changes despite a dirty tree")
    args = parser.parse_args(argv)

    report = run_review(args)
    payload = json.dumps(
        {**asdict(report), "findings": [{**asdict(f), "blocking": f.blocking} for f in report.findings]}, indent=2
    )
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(payload + "\n", encoding="utf-8")
    print(payload)
    print(f"greptile-review: {report.verdict}", file=sys.stderr)
    return EXIT_FOR_VERDICT[report.verdict]


if __name__ == "__main__":
    sys.exit(main())
