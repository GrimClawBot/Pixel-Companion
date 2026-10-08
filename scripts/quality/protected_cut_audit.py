#!/usr/bin/env python3
"""Read-only fail-closed first-cut GitHub branch protection and approval audit.

Never merges, approves, publishes, updates policies or changes any Git ref.
A passing result is only a handoff for explicit human merge authorization.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess

REPO_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")


def run_command(arguments: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        arguments, capture_output=True, text=True, timeout=45, check=False
    )


def evaluate_cut(
    pr: dict,
    protection: dict | None,
    *,
    base: str,
    candidate_head: str,
    git_head: str,
    git_ancestor: bool,
    virtual_merge_clean: bool,
) -> dict:
    """Use verified source metadata, not a PR author's assertion of approval."""
    blockers: list[str] = []
    checks = [
        check for check in (pr.get("statusCheckRollup") or [])
        if isinstance(check, dict) and check.get("name")
    ]
    check_names = {check["name"] for check in checks}
    # A passed CodeRabbit check is not a substitute for native-checks.
    # Requiring any random successful check is a fail-open release gate.
    results_by_name: dict[str, list[str | None]] = {}
    for check in checks:
        results_by_name.setdefault(check["name"], []).append(check.get("conclusion"))
    statuses_all_successful = bool(checks) and all(
        check.get("conclusion") == "SUCCESS" for check in checks
    )
    review_rule = (
        (protection or {}).get("required_pull_request_reviews") or {}
    )
    if not isinstance(review_rule, dict):
        review_rule = {}
    required_count = review_rule.get("required_approving_review_count")
    checks_rule = (protection or {}).get("required_status_checks") or {}
    if not isinstance(checks_rule, dict):
        checks_rule = {}
    protected_review = (
        type(required_count) is int and required_count >= 1
    )
    protected_checks = bool(checks_rule.get("contexts") or checks_rule.get("checks"))
    required_contexts = set(checks_rule.get("contexts") or [])
    required_contexts.update(
        check["context"] for check in (checks_rule.get("checks") or [])
        if isinstance(check, dict) and isinstance(check.get("context"), str)
    )
    # A context is genuinely required only when it is a nonempty name
    # whose exact GitHub check has a successful conclusion on this PR.
    required_names = {
        context for context in required_contexts
        if isinstance(context, str) and context.strip()
    }
    protected_checks = protected_checks and bool(required_names)
    missing_required = sorted(required_names - check_names)
    passing_required = all(
        len(results_by_name.get(name, [])) == 1
        and results_by_name[name][0] == "SUCCESS"
        for name in required_names
    )
    checks_successful = statuses_all_successful and passing_required
    admin_policy = (protection or {}).get("enforce_admins") or {}
    force_policy = (protection or {}).get("allow_force_pushes") or {}
    delete_policy = (protection or {}).get("allow_deletions") or {}
    admin_enforced = isinstance(admin_policy, dict) and admin_policy.get("enabled") is True
    strict_ci = checks_rule.get("strict") is True
    dismiss_stale = review_rule.get("dismiss_stale_reviews") is True
    last_push_review = review_rule.get("require_last_push_approval") is True
    no_force_push = isinstance(force_policy, dict) and force_policy.get("enabled") is False
    no_deletion = isinstance(delete_policy, dict) and delete_policy.get("enabled") is False
    if not protected_review:
        blockers.append("main lacks enforced approving PR review requirement")
    if not protected_checks:
        blockers.append("main lacks required CI status checks")
    if missing_required or not passing_required:
        blockers.append("a required named CI check is absent, repeated or unsuccessful")
    if not admin_enforced:
        blockers.append("main protection is not enforced for administrators")
    if not strict_ci:
        blockers.append("main required checks do not enforce current base")
    if not dismiss_stale or not last_push_review:
        blockers.append("main can reuse stale or self-push approvals")
    if not no_force_push or not no_deletion:
        blockers.append("main permits force pushes or deletion")
    if pr.get("isDraft") is not False:
        blockers.append("PR is still draft")
    if pr.get("reviewDecision") != "APPROVED":
        blockers.append("independent GitHub APPROVED review not recorded")
    if pr.get("mergeable") != "MERGEABLE":
        blockers.append("GitHub reports unresolved mergeability")
    if not checks_successful:
        blockers.append("native PR status checks are pending, absent or failing")
    if pr.get("baseRefName") != base:
        blockers.append("PR does not target requested protected base")
    if pr.get("headRefName") != candidate_head:
        blockers.append("candidate head branch differs from requested cut")
    head_sha = pr.get("headRefOid")
    if not isinstance(head_sha, str) or not re.fullmatch(r"[a-fA-F0-9]{40}", head_sha):
        blockers.append("GitHub head SHA missing or invalid")
    elif head_sha != git_head:
        blockers.append("GitHub head SHA differs from inspected Git commit")
    if not git_ancestor or not virtual_merge_clean:
        blockers.append("virtual merge or ancestry validation failed")
    return {
        "schemaVersion": 1,
        "pr_number": pr.get("number"),
        "base": base,
        "head_branch": candidate_head,
        "head_commit": git_head,
        "github_head_matches_local_git": head_sha == git_head,
        "branch_requires_approval": protected_review,
        "branch_requires_ci": protected_checks,
        "required_check_names": sorted(required_names),
        "missing_required_check_names": missing_required,
        "required_ci_checks_all_successful": passing_required,
        "main_enforces_admins": admin_enforced,
        "main_requires_fresh_base": strict_ci,
        "main_requires_fresh_independent_review": dismiss_stale and last_push_review,
        "main_blocks_force_pushes_and_deletion": no_force_push and no_deletion,
        "required_approving_review_count": required_count if protected_review else 0,
        "pr_approved": pr.get("reviewDecision") == "APPROVED",
        "pr_draft": pr.get("isDraft") is True,
        "ci_complete_and_successful": checks_successful,
        "git_main_is_ancestor": git_ancestor,
        "git_virtual_merge_clean": virtual_merge_clean,
        "blockers": blockers,
        "ready_for_explicit_human_merge_decision": not blockers,
        "merge_authorized_by_this_report": False,
        "main_modified": False,
        "provider_settings_modified": False,
    }


def checked_json(command: list[str]) -> dict | None:
    result = run_command(command)
    if result.returncode != 0:
        return None
    try:
        data = json.loads(result.stdout)
    except ValueError:
        return None
    return data if isinstance(data, dict) else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="GrimClawBot/Pixel-Companion")
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--base", default="main")
    parser.add_argument("--head", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if (not REPO_PATTERN.fullmatch(args.repo) or args.pr < 1
            or not re.fullmatch(r"[A-Za-z0-9_.-]+", args.base)
            or not re.fullmatch(r"[A-Za-z0-9_./-]+", args.head)):
        print("CUT_AUDIT: INVALID_REQUEST")
        return 2
    pr = checked_json([
        "gh", "pr", "view", str(args.pr), "--repo", args.repo, "--json",
        "number,headRefOid,headRefName,baseRefName,isDraft,reviewDecision,"
        "mergeable,statusCheckRollup",
    ])
    if pr is None:
        print("CUT_AUDIT: INCOMPLETE (PR metadata unavailable)")
        return 2

    # 404 means no legacy protection. A separately configured ruleset may
    # exist, but is not assumed sufficient unless inspected by the reviewer.
    protection = checked_json([
        "gh", "api", "repos/" + args.repo + "/branches/" + args.base + "/protection",
    ])
    local_tip = run_command(["git", "rev-parse", "--verify", "origin/" + args.head])
    if local_tip.returncode != 0:
        print("CUT_AUDIT: INCOMPLETE (candidate ref unavailable)")
        return 2
    head_sha = local_tip.stdout.strip()
    ancestor = run_command([
        "git", "merge-base", "--is-ancestor", "origin/" + args.base, head_sha
    ]).returncode == 0
    virtual = run_command([
        "git", "merge-tree", "--write-tree", "origin/" + args.base, head_sha
    ])
    report = evaluate_cut(
        pr, protection, base=args.base, candidate_head=args.head,
        git_head=head_sha, git_ancestor=ancestor,
        virtual_merge_clean=virtual.returncode == 0,
    )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("CUT_AUDIT:", "REVIEW_READY" if not report["blockers"] else "BLOCKED")
    print("PR_NUMBER:", args.pr)
    print("HEAD_SHA_MATCH:", report["github_head_matches_local_git"])
    print("BASE_APPROVAL_PROTECTION:", report["branch_requires_approval"])
    print("BASE_CI_PROTECTION:", report["branch_requires_ci"])
    print("GITHUB_APPROVED:", report["pr_approved"])
    print("VIRTUAL_MERGE_CLEAN:", report["git_virtual_merge_clean"])
    print("BLOCKERS:", "; ".join(report["blockers"]) or "none")
    print("MAIN_MUTATED: NO")
    return 3 if report["blockers"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
