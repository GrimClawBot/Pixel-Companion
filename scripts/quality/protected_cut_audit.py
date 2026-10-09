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


def independent_approvals(reviews: list[dict], head_sha: str, author: str) -> list[str]:
    """Only latest, exact-head, human, non-author approvals may count.

    Review lists come from GitHub REST in submission order. A more recent
    CHANGES_REQUESTED or DISMISSED state replaces an older approval from
    the same reviewer. This supplements (never replaces) GitHub's own
    branch-protection enforcement and explicit human merge authorization.
    """
    latest: dict[str, dict] = {}
    for review in reviews:
        if not isinstance(review, dict):
            continue
        user = review.get("user")
        if not isinstance(user, dict):
            continue
        login = user.get("login")
        if not isinstance(login, str) or not login:
            continue
        # COMMENTED is additive feedback, NOT a retraction of an approval.
        # Only decision-changing submissions update the effective review.
        if review.get("state") not in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
            continue
        latest[login.casefold()] = review
    return sorted(
        reviewer for reviewer, review in latest.items()
        if reviewer != author.casefold()
        and review.get("state") == "APPROVED"
        and review.get("commit_id") == head_sha
        and review["user"].get("type") == "User"
        and not reviewer.endswith("[bot]")
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
    git_base_sha: str = "",
    live_base_sha: str = "",
    reviews: list[dict] | None = None,
    check_runs: list[dict] | None = None,
) -> dict:
    """Use verified source metadata, not a PR author's assertion of approval."""
    blockers: list[str] = []
    checks = [
        check for check in (pr.get("statusCheckRollup") or [])
        if isinstance(check, dict) and check.get("name")
    ]
    check_names = {check["name"] for check in checks}
    # A PR's status rollup can contain checks from other PRs which share the
    # same immutable head SHA. Never count those unrelated runs as approval.
    # A passed CodeRabbit check is not a substitute for native-checks.
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
    # Branch protection pins each required workflow context to an App ID.
    # Same-head commits can legitimately have multiple PR-specific CI runs.
    # Scope each run to THIS PR and link it to the exact PR rollup entry,
    # rather than accepting a passing check from a different PR.
    required_apps: dict[str, int] = {}
    for rule in (checks_rule.get("checks") or []):
        if not isinstance(rule, dict):
            continue
        name = rule.get("context")
        app_id = rule.get("app_id")
        if isinstance(name, str) and type(app_id) is int and app_id > 0:
            required_apps[name] = app_id
    trusted_producers = (
        required_names == set(required_apps)
        and bool(required_names)
        and isinstance(check_runs, list)
    )
    producer_matches: dict[str, bool] = {}
    if trusted_producers:
        for name in sorted(required_names):
            associated = [
                run for run in check_runs or []
                if isinstance(run, dict) and run.get("name") == name
                and isinstance(run.get("pull_requests"), list)
                and any(
                    isinstance(link, dict) and link.get("number") == pr.get("number")
                    for link in run["pull_requests"]
                )
            ]
            matched_rollup = (
                [
                    check for check in checks
                    if check.get("name") == name
                    and check.get("detailsUrl") == associated[0].get("details_url")
                ] if len(associated) == 1 else []
            )
            producer_matches[name] = (
                len(associated) == 1
                and isinstance(associated[0].get("details_url"), str)
                and bool(associated[0]["details_url"])
                and len(matched_rollup) == 1
                and matched_rollup[0].get("status") == "COMPLETED"
                and matched_rollup[0].get("conclusion") == "SUCCESS"
                and associated[0].get("head_sha") == git_head
                and associated[0].get("status") == "completed"
                and associated[0].get("conclusion") == "success"
                and isinstance(associated[0].get("app"), dict)
                and associated[0]["app"].get("id") == required_apps[name]
            )
    producers_verified = trusted_producers and all(producer_matches.values())
    passing_required = producers_verified
    other_named_checks_successful = all(
        check.get("conclusion") == "SUCCESS"
        for check in checks if check["name"] not in required_names
    )
    checks_successful = passing_required and other_named_checks_successful
    if not producers_verified:
        blockers.append("required native CI producer App identity not verified")
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
    github_base_sha = pr.get("baseRefOid")
    sha_pattern = r"[a-fA-F0-9]{40}"
    base_matches = (
        isinstance(github_base_sha, str)
        and re.fullmatch(sha_pattern, github_base_sha) is not None
        and github_base_sha == git_base_sha == live_base_sha
    )
    if not base_matches:
        blockers.append("GitHub, remote main, and local base commit differ")
    author_data = pr.get("author") or {}
    author = author_data.get("login", "") if isinstance(author_data, dict) else ""
    eligible = independent_approvals(reviews or [], git_head, author)
    if not author or not protected_review or len(eligible) < required_count:
        blockers.append("missing independent human approval on exact current head")
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
        "github_base_matches_live_and_local_git": base_matches,
        "independent_human_approving_reviewers": eligible,
        "branch_requires_approval": protected_review,
        "branch_requires_ci": protected_checks,
        "required_check_names": sorted(required_names),
        "missing_required_check_names": missing_required,
        "required_ci_checks_all_successful": passing_required,
        "required_ci_producer_apps_verified": producers_verified,
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


def checked_reviews(command: list[str]) -> list[dict] | None:
    result = run_command(command)
    if result.returncode != 0:
        return None
    try:
        data = json.loads(result.stdout)
    except ValueError:
        return None
    if not isinstance(data, list):
        return None
    if all(isinstance(page, list) for page in data):
        data = [item for page in data for item in page]
    return data if all(isinstance(item, dict) for item in data) else None


def read_live_base_sha(repo: str, base: str) -> str | None:
    """Read a fresh, exact base commit from GitHub; reject malformed data."""
    response = checked_json([
        "gh", "api", "repos/" + repo + "/branches/" + base,
    ])
    if not isinstance(response, dict):
        return None
    commit = response.get("commit")
    sha = commit.get("sha") if isinstance(commit, dict) else None
    return sha if isinstance(sha, str) and re.fullmatch(r"[a-fA-F0-9]{40}", sha) else None


def finalize_base_readback(
    report: dict, *, pinned_base_sha: str, latest_base_sha: str | None
) -> dict:
    """Fail closed if main has moved since the first read or is unavailable."""
    stable = (
        isinstance(latest_base_sha, str)
        and re.fullmatch(r"[a-fA-F0-9]{40}", latest_base_sha) is not None
        and latest_base_sha == pinned_base_sha
        and report["github_base_matches_live_and_local_git"]
    )
    report["live_base_stable_at_final_readback"] = stable
    report["final_base_check_available"] = latest_base_sha is not None
    if not stable:
        report["blockers"].append(
            "live GitHub base moved or became unavailable before final readiness"
        )
    report["ready_for_explicit_human_merge_decision"] = not report["blockers"]
    return report


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
        "number,headRefOid,headRefName,baseRefName,baseRefOid,author,"
        "isDraft,reviewDecision,mergeable,statusCheckRollup",
    ])
    if pr is None:
        print("CUT_AUDIT: INCOMPLETE (PR metadata unavailable)")
        return 2

    # 404 means no legacy protection. A separately configured ruleset may
    # exist, but is not assumed sufficient unless inspected by the reviewer.
    protection = checked_json([
        "gh", "api", "repos/" + args.repo + "/branches/" + args.base + "/protection",
    ])
    live_sha = read_live_base_sha(args.repo, args.base)
    review_records = checked_reviews([
        "gh", "api", "--paginate", "--slurp",
        "repos/" + args.repo + "/pulls/" + str(args.pr) + "/reviews?per_page=100",
    ])
    if live_sha is None or review_records is None:
        print("CUT_AUDIT: INCOMPLETE (live base or review data unavailable)")
        return 2
    local_base = run_command([
        "git", "rev-parse", "--verify", "origin/" + args.base,
    ])
    if local_base.returncode != 0:
        print("CUT_AUDIT: INCOMPLETE (local base unavailable)")
        return 2
    local_base_sha = local_base.stdout.strip()
    local_tip = run_command(["git", "rev-parse", "--verify", "origin/" + args.head])
    if local_tip.returncode != 0:
        print("CUT_AUDIT: INCOMPLETE (candidate ref unavailable)")
        return 2
    head_sha = local_tip.stdout.strip()
    # Always validate immutable pinned commits, never mutable origin/main.
    ancestor = run_command([
        "git", "merge-base", "--is-ancestor", local_base_sha, head_sha
    ]).returncode == 0
    virtual = run_command([
        "git", "merge-tree", "--write-tree", local_base_sha, head_sha
    ])
    runs_response = checked_json([
        "gh", "api",
        "repos/" + args.repo + "/commits/" + head_sha + "/check-runs?per_page=100",
    ])
    if runs_response is None or not isinstance(runs_response.get("check_runs"), list):
        print("CUT_AUDIT: INCOMPLETE (CI producer metadata unavailable)")
        return 2
    if runs_response.get("total_count") != len(runs_response["check_runs"]):
        print("CUT_AUDIT: INCOMPLETE (CI producer result pagination incomplete)")
        return 2
    report = evaluate_cut(
        pr, protection, base=args.base, candidate_head=args.head,
        git_head=head_sha, git_ancestor=ancestor,
        virtual_merge_clean=virtual.returncode == 0,
        git_base_sha=local_base_sha, live_base_sha=live_sha,
        reviews=review_records,
        check_runs=runs_response["check_runs"],
    )
    # Greptile PC-061: re-read GitHub main at the very end of all
    # slow review/CI/Git calls. A prior correct base no longer counts
    # if main moved before this check (or the API read fails).
    last_base_sha = read_live_base_sha(args.repo, args.base)
    report = finalize_base_readback(
        report, pinned_base_sha=local_base_sha, latest_base_sha=last_base_sha
    )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("CUT_AUDIT:", "REVIEW_READY" if not report["blockers"] else "BLOCKED")
    print("PR_NUMBER:", args.pr)
    print("HEAD_SHA_MATCH:", report["github_head_matches_local_git"])
    print("BASE_SHA_MATCH:", report["github_base_matches_live_and_local_git"])
    print("FINAL_BASE_SHA_STABLE:", report["live_base_stable_at_final_readback"])
    print("INDEPENDENT_EXACT_HEAD_REVIEWS:", len(report["independent_human_approving_reviewers"]))
    print("BASE_APPROVAL_PROTECTION:", report["branch_requires_approval"])
    print("BASE_CI_PROTECTION:", report["branch_requires_ci"])
    print("REQUIRED_CI_APP_IDENTITY:", report["required_ci_producer_apps_verified"])
    print("GITHUB_APPROVED:", report["pr_approved"])
    print("VIRTUAL_MERGE_CLEAN:", report["git_virtual_merge_clean"])
    print("BLOCKERS:", "; ".join(report["blockers"]) or "none")
    print("MAIN_MUTATED: NO")
    if not report["final_base_check_available"]:
        return 2
    return 3 if report["blockers"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
