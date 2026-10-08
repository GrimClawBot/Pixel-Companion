#!/usr/bin/env python3
"""Read-only Pixel Companion PR stack audit. NEVER merges or updates refs.

This is a reviewer aid, not an automated approval system. A successful
native build/CI status is insufficient without independent reviews and
manual acceptance.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path

GITHUB_FIELDS = (
    "number,headRefName,baseRefName,isDraft,reviewDecision,"
    "mergeable,statusCheckRollup"
)
VALID_CHECKS = {"SUCCESS", "NEUTRAL", "SKIPPED"}


def analyze(prs: list[dict], tip: str, base: str = "main") -> dict:
    """Return a machine-readable finding set using only GitHub public metadata."""
    heads = {p["headRefName"]: p for p in prs}
    numbers = [p["number"] for p in prs]
    repeated_heads = [
        name for name, count in Counter(p["headRefName"] for p in prs).items()
        if count > 1
    ]
    repeated_numbers = [
        number for number, count in Counter(numbers).items() if count > 1
    ]
    root_prs = sorted(
        p["number"] for p in prs if p["baseRefName"] == base
    )
    dangling = sorted(
        p["number"] for p in prs
        if p["baseRefName"] != base and p["baseRefName"] not in heads
    )

    trace: list[int] = []
    seen: set[str] = set()
    cursor = tip
    has_cycle = False
    reaches_base = False
    while cursor in heads:
        if cursor in seen:
            has_cycle = True
            break
        seen.add(cursor)
        pr = heads[cursor]
        trace.append(pr["number"])
        cursor = pr["baseRefName"]
    if cursor == base:
        reaches_base = True

    pending_reviews = sorted(
        p["number"] for p in prs
        if p.get("reviewDecision") != "APPROVED"
    )
    review_changes_requested = sorted(
        p["number"] for p in prs
        if p.get("reviewDecision") == "CHANGES_REQUESTED"
    )
    drafts = sorted(p["number"] for p in prs if p.get("isDraft", True))
    ci_failing: list[int] = []
    ci_pending: list[int] = []
    ci_success: list[int] = []
    merge_conflicts: list[int] = []
    merge_unknown: list[int] = []
    for pr in prs:
        checks = [
            check for check in (pr.get("statusCheckRollup") or [])
            if isinstance(check, dict) and check.get("name")
        ]
        # GitHub's CLI can report an in-progress check conclusion as
        # either null or an empty string. Neither is a failed check.
        results = [check.get("conclusion") or None for check in checks]
        if any(result not in (None, *VALID_CHECKS) for result in results):
            ci_failing.append(pr["number"])
        elif not checks or any(result is None for result in results):
            ci_pending.append(pr["number"])
        else:
            ci_success.append(pr["number"])
        mergeability = pr.get("mergeable")
        if mergeability == "CONFLICTING":
            merge_conflicts.append(pr["number"])
        elif mergeability != "MERGEABLE":
            merge_unknown.append(pr["number"])

    tip_numbers = set(trace)
    outside_tip = sorted(set(numbers) - tip_numbers)
    blockers = []
    if repeated_heads or repeated_numbers:
        blockers.append("duplicate PR identity in source data")
    if dangling or not reaches_base or has_cycle:
        blockers.append("broken or cyclic dependency chain")
    if len(root_prs) != 1 or outside_tip:
        blockers.append("unreconciled parallel PR branches")
    if pending_reviews:
        blockers.append("missing independent GitHub approval decisions")
    if drafts:
        blockers.append("PRs remain draft")
    if ci_failing or ci_pending:
        blockers.append("CI failure or incomplete check status")
    if merge_conflicts or merge_unknown:
        blockers.append("mergeability unresolved")
    return {
        "schemaVersion": 1,
        "tip": tip,
        "base": base,
        "open_pr_count": len(prs),
        "base_root_pr_numbers": root_prs,
        "draft_pr_numbers": drafts,
        "unapproved_pr_numbers": pending_reviews,
        "changes_requested_pr_numbers": review_changes_requested,
        "failing_ci_pr_numbers": sorted(ci_failing),
        "pending_ci_pr_numbers": sorted(ci_pending),
        "passing_ci_pr_count": len(ci_success),
        "merge_conflict_pr_numbers": sorted(merge_conflicts),
        "unknown_mergeability_pr_numbers": sorted(merge_unknown),
        "tip_chain_pr_numbers_newest_first": trace,
        "tip_reaches_base": reaches_base,
        "cyclic_tip_chain": has_cycle,
        "dangling_base_pr_numbers": dangling,
        "outside_tip_chain_pr_numbers": outside_tip,
        "duplicate_head_branches": repeated_heads,
        "duplicate_pr_numbers": repeated_numbers,
        "merge_allowed_by_this_audit": False,
        "human_review_required": True,
        "blockers": blockers,
        "candidate_ready_for_human_merge_decision": not blockers,
    }


def run_command(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        args, capture_output=True, text=True, timeout=45, check=False
    )


def git_probe(main: str, tip: str) -> dict:
    """Virtual merge-tree, no checkout, no worktree mutation, no actual merge."""
    remote = "origin/" + main
    cmd = ["git", "merge-base", "--is-ancestor", remote, tip]
    ancestor = run_command(cmd)
    # git merge-tree can report conflicts and uses Git's object database
    # without updating branches or the worktree. Never print raw diff data.
    virtual = run_command(["git", "merge-tree", "--write-tree", remote, tip])
    return {
        "main_is_ancestor_of_candidate": ancestor.returncode == 0,
        "virtual_merge_clean": virtual.returncode == 0,
        "virtual_merge_tree_created": (
            virtual.returncode == 0 and len(virtual.stdout.strip().splitlines()[0]) == 40
            if virtual.stdout.strip() else False
        ),
        "refs_updated": False,
        "worktree_modified": False,
    }


def classify_parallel_heads(
    prs: list[dict], tip: str, outside_numbers: list[int]
) -> dict[str, list[int]]:
    """Check commit ancestry for out-of-chain PR heads, never just branch labels.

    If the entire head is an ancestor of the integration candidate it is
    already included, but its older PR still needs human review/reconciliation.
    """
    by_number = {p["number"]: p for p in prs}
    results: dict[str, list[int]] = {
        "already_in_candidate": [], "divergent_changes": [],
        "unresolved_git_ref": [],
    }
    for number in outside_numbers:
        head = "origin/" + by_number[number]["headRefName"]
        ref = run_command(["git", "rev-parse", "--verify", "--quiet", head])
        if ref.returncode != 0:
            results["unresolved_git_ref"].append(number)
            continue
        ancestry = run_command(["git", "merge-base", "--is-ancestor", head, tip])
        category = "already_in_candidate" if ancestry.returncode == 0 else "divergent_changes"
        results[category].append(number)
    return results


def audit(prs: list[dict], tip: str, base: str, check_git: bool) -> dict:
    report = analyze(prs, tip=tip, base=base)
    if check_git:
        git = git_probe(base, tip)
        report["git_readonly_probe"] = git
        parallel = classify_parallel_heads(
            prs, tip, report["outside_tip_chain_pr_numbers"]
        )
        report["parallel_head_ancestry"] = parallel
        if not git["main_is_ancestor_of_candidate"] or not git["virtual_merge_clean"]:
            report["blockers"].append("git virtual merge/ancestry check failed")
            report["candidate_ready_for_human_merge_decision"] = False
        if parallel["divergent_changes"] or parallel["unresolved_git_ref"]:
            report["blockers"].append("parallel head requires separate diff/review")
            report["candidate_ready_for_human_merge_decision"] = False
    else:
        report["git_readonly_probe"] = {"not_run": True}
        report["parallel_head_ancestry"] = {"not_run": True}
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tip", required=True, help="Current candidate head branch")
    parser.add_argument("--base", default="main", help="Protected destination branch")
    parser.add_argument("--input", type=Path, help="Test fixture instead of GitHub CLI")
    parser.add_argument("--output", type=Path, help="Write JSON report (never provider config)")
    parser.add_argument("--skip-git", action="store_true")
    args = parser.parse_args()
    try:
        if args.input:
            prs = json.loads(args.input.read_text())
        else:
            proc = run_command([
                "gh", "pr", "list", "--state", "open",
                "--limit", "200", "--json", GITHUB_FIELDS,
            ])
            if proc.returncode != 0:
                print("PREMERGE_AUDIT: INCOMPLETE (GitHub metadata unavailable)")
                return 2
            prs = json.loads(proc.stdout)
        if not isinstance(prs, list):
            raise ValueError("PR source must be a list")
        report = audit(prs, tip=args.tip, base=args.base, check_git=not args.skip_git)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print("PREMERGE_AUDIT: " + (
            "REVIEW_READY" if report["candidate_ready_for_human_merge_decision"]
            else "BLOCKED"
        ))
        print("OPEN_PRS:", report["open_pr_count"])
        print("DIRECT_MAIN_ROOTS:", report["base_root_pr_numbers"])
        print("TIP_CHAIN_DEPTH:", len(report["tip_chain_pr_numbers_newest_first"]))
        parallel = report["parallel_head_ancestry"]
        if "already_in_candidate" in parallel:
            print("OLDER_HEADS_ALREADY_IN_CANDIDATE:", len(parallel["already_in_candidate"]))
            print("DIVERGENT_HEADS:", parallel["divergent_changes"])
            print("UNRESOLVED_HEADS:", parallel["unresolved_git_ref"])
        print("UNAPPROVED:", len(report["unapproved_pr_numbers"]))
        print("DRAFT:", len(report["draft_pr_numbers"]))
        print("CI_FAIL_OR_PENDING:", len(report["failing_ci_pr_numbers"]) +
              len(report["pending_ci_pr_numbers"]))
        print("BLOCKERS:", "; ".join(report["blockers"]) or "none")
        print("MAIN_MODIFIED: NO")
        return 3 if report["blockers"] else 0
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired, IndexError):
        print("PREMERGE_AUDIT: INCOMPLETE (could not validate metadata)")
        return 2


if __name__ == "__main__":
    sys.exit(main())
