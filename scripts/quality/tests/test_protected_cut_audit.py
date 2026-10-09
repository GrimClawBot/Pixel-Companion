"""Integration merge protection gate must fail closed on missing evidence."""
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from scripts.quality.protected_cut_audit import (
    evaluate_cut, finalize_base_readback, independent_approvals, main, read_live_base_sha,
)


DEFAULT_RUN_URL = "https://github.com/example/pixel/actions/runs/123/job/456"


def pr(**overrides):
    result = {
        "number": 51, "baseRefName": "main",
        "headRefName": "integration/pixel-companion-readonly-alpha",
        "headRefOid": "a" * 40, "baseRefOid": "b" * 40,
        "author": {"login": "GrimClawBot"},
        "isDraft": False, "reviewDecision": "APPROVED",
        "mergeable": "MERGEABLE",
        "statusCheckRollup": [{
            "name": "native-checks", "conclusion": "SUCCESS",
            "status": "COMPLETED", "detailsUrl": DEFAULT_RUN_URL,
        }],
    }
    result.update(overrides)
    return result


HUMAN_REVIEW = [
    {
        "user": {"login": "IndependentReviewer", "type": "User"},
        "state": "APPROVED", "commit_id": "a" * 40,
    }
]

PROTECTION = {
    "required_pull_request_reviews": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews": True,
        "require_last_push_approval": True,
    },
    "required_status_checks": {
        "strict": True, "checks": [{"context": "native-checks", "app_id": 15368}],
    },
    "enforce_admins": {"enabled": True},
    "allow_force_pushes": {"enabled": False},
    "allow_deletions": {"enabled": False},
}


def audit_default_check_run():
    return {
        "name": "native-checks", "head_sha": "a" * 40,
        "status": "completed", "conclusion": "success",
        "app": {"id": 15368},
        "details_url": DEFAULT_RUN_URL,
        "pull_requests": [{"number": 51}],
    }


def audit(item=None, policy=PROTECTION, **overrides):
    defaults = {
        "base": "main",
        "candidate_head": "integration/pixel-companion-readonly-alpha",
        "git_head": "a" * 40,
        "git_ancestor": True,
        "virtual_merge_clean": True,
        "git_base_sha": "b" * 40,
        "live_base_sha": "b" * 40,
        "reviews": HUMAN_REVIEW,
        "check_runs": [audit_default_check_run()],
    }
    defaults.update(overrides)
    return evaluate_cut(item or pr(), policy, **defaults)


class ProtectedCutAuditTests(unittest.TestCase):
    def test_fully_reviewed_protected_clean_cut_is_only_human_review_ready(self):
        report = audit()
        self.assertEqual(report["blockers"], [])
        self.assertTrue(report["ready_for_explicit_human_merge_decision"])
        self.assertFalse(report["merge_authorized_by_this_report"])
        self.assertFalse(report["main_modified"])

    def test_unprotected_main_refuses_to_promote_even_green_pr(self):
        report = audit(policy=None)
        self.assertFalse(report["branch_requires_approval"])
        self.assertFalse(report["branch_requires_ci"])
        self.assertFalse(report["ready_for_explicit_human_merge_decision"])

    def test_final_live_base_readback_can_be_review_ready_only_if_unchanged(self):
        result = finalize_base_readback(
            audit(), pinned_base_sha="b" * 40, latest_base_sha="b" * 40
        )
        self.assertTrue(result["live_base_stable_at_final_readback"])
        self.assertTrue(result["ready_for_explicit_human_merge_decision"])
        self.assertFalse(result["merge_authorized_by_this_report"])

    def test_main_advancing_after_first_read_refuses_ready(self):
        # All initial GitHub/local/PR commits match. The final read differs.
        result = finalize_base_readback(
            audit(), pinned_base_sha="b" * 40, latest_base_sha="c" * 40
        )
        self.assertTrue(result["github_base_matches_live_and_local_git"])
        self.assertFalse(result["live_base_stable_at_final_readback"])
        self.assertFalse(result["ready_for_explicit_human_merge_decision"])

    def test_final_base_lookup_failure_refuses_ready(self):
        result = finalize_base_readback(
            audit(), pinned_base_sha="b" * 40, latest_base_sha=None
        )
        self.assertFalse(result["final_base_check_available"])
        self.assertFalse(result["ready_for_explicit_human_merge_decision"])

    def test_first_base_mismatch_cannot_be_rescued_by_final_matching_ref(self):
        report = audit(live_base_sha="c" * 40)
        result = finalize_base_readback(
            report, pinned_base_sha="b" * 40, latest_base_sha="b" * 40
        )
        self.assertFalse(result["live_base_stable_at_final_readback"])
        self.assertFalse(result["ready_for_explicit_human_merge_decision"])

    @patch("scripts.quality.protected_cut_audit.checked_json")
    def test_live_base_read_handles_unavailable_and_bad_metadata(self, mock_json):
        for response in (None, {}, {"commit": None}, {"commit": {"sha": "bad"}}):
            with self.subTest(response=response):
                mock_json.return_value = response
                self.assertIsNone(read_live_base_sha("Owner/Repo", "main"))
        mock_json.return_value = {"commit": {"sha": "b" * 40}}
        self.assertEqual(read_live_base_sha("Owner/Repo", "main"), "b" * 40)

    def test_end_to_end_main_checks_pinned_base_and_rechecks_live_sha(self):
        # All early metadata and reviews are green. A concurrent update to
        # main between those reads and the final API call must block.
        initial = {"commit": {"sha": "b" * 40}}
        shifted = {"commit": {"sha": "c" * 40}}
        producer = {"check_runs": [audit_default_check_run()], "total_count": 1}
        git_results = [
            SimpleNamespace(returncode=0, stdout="b" * 40 + "\n"),
            SimpleNamespace(returncode=0, stdout="a" * 40 + "\n"),
            SimpleNamespace(returncode=0, stdout=""),
            SimpleNamespace(returncode=0, stdout=""),
        ]
        with patch("scripts.quality.protected_cut_audit.checked_json") as read_json, (
            patch("scripts.quality.protected_cut_audit.checked_reviews", return_value=HUMAN_REVIEW)
        ), patch("scripts.quality.protected_cut_audit.run_command", side_effect=git_results) as git, (
            patch("sys.argv", [
                "protected_cut_audit", "--pr", "51",
                "--head", "integration/pixel-companion-readonly-alpha",
            ])
        ):
            read_json.side_effect = [pr(), PROTECTION, initial, producer, shifted]
            self.assertEqual(main(), 3)
            self.assertEqual(read_json.call_count, 5)
            commands = [item.args[0] for item in git.call_args_list]
            self.assertIn(["git", "merge-base", "--is-ancestor", "b" * 40, "a" * 40], commands)
            self.assertIn(["git", "merge-tree", "--write-tree", "b" * 40, "a" * 40], commands)
            self.assertNotIn("origin/main", commands[2])
            self.assertNotIn("origin/main", commands[3])

    def test_end_to_end_missing_final_base_read_fails_closed(self):
        initial = {"commit": {"sha": "b" * 40}}
        producer = {"check_runs": [audit_default_check_run()], "total_count": 1}
        git_results = [
            SimpleNamespace(returncode=0, stdout="b" * 40 + "\n"),
            SimpleNamespace(returncode=0, stdout="a" * 40 + "\n"),
            SimpleNamespace(returncode=0, stdout=""),
            SimpleNamespace(returncode=0, stdout=""),
        ]
        with patch("scripts.quality.protected_cut_audit.checked_json") as read_json, (
            patch("scripts.quality.protected_cut_audit.checked_reviews", return_value=HUMAN_REVIEW)
        ), patch("scripts.quality.protected_cut_audit.run_command", side_effect=git_results), (
            patch("sys.argv", [
                "protected_cut_audit", "--pr", "51",
                "--head", "integration/pixel-companion-readonly-alpha",
            ])
        ):
            read_json.side_effect = [pr(), PROTECTION, initial, producer, None]
            self.assertEqual(main(), 2)

    def test_stale_base_sha_blocks_even_when_git_ancestry_clean(self):
        result = audit(live_base_sha="c" * 40)
        self.assertFalse(result["github_base_matches_live_and_local_git"])
        self.assertFalse(result["ready_for_explicit_human_merge_decision"])

    def test_stale_local_base_ref_blocks(self):
        self.assertFalse(
            audit(git_base_sha="c" * 40)["ready_for_explicit_human_merge_decision"]
        )

    def test_human_approval_on_prior_commit_is_not_current_approval(self):
        old = [{**HUMAN_REVIEW[0], "commit_id": "d" * 40}]
        result = audit(reviews=old)
        self.assertFalse(result["ready_for_explicit_human_merge_decision"])

    def test_bot_and_pr_author_approvals_are_not_independent(self):
        bot = {"user": {"login": "reviewbot[bot]", "type": "Bot"},
               "state": "APPROVED", "commit_id": "a" * 40}
        author = {"user": {"login": "GrimClawBot", "type": "User"},
                  "state": "APPROVED", "commit_id": "a" * 40}
        result = audit(reviews=[bot, author])
        self.assertEqual(result["independent_human_approving_reviewers"], [])
        self.assertFalse(result["ready_for_explicit_human_merge_decision"])

    def test_latest_changes_requested_overrides_prior_approval(self):
        changed = {**HUMAN_REVIEW[0], "state": "CHANGES_REQUESTED"}
        self.assertEqual(
            independent_approvals([HUMAN_REVIEW[0], changed], "a" * 40, "GrimClawBot"),
            [],
        )

    def test_missing_review_data_is_not_approval(self):
        self.assertFalse(audit(reviews=[])["ready_for_explicit_human_merge_decision"])

    def test_missing_or_null_policy_components_fail_closed(self):
        for key in ("enforce_admins", "allow_force_pushes", "allow_deletions"):
            with self.subTest(key=key):
                policy = {**PROTECTION, key: None}
                self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_no_review_requirement_refuses_promotion(self):
        policy = {**PROTECTION, "required_pull_request_reviews": None}
        self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_no_required_ci_refuses_promotion(self):
        policy = {**PROTECTION, "required_status_checks": None}
        self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_wrong_app_with_correct_name_is_not_trusted(self):
        fake = [{
            "name": "native-checks", "head_sha": "a" * 40,
            "status": "completed", "conclusion": "success",
            "app": {"id": 99999},
        }]
        report = audit(check_runs=fake)
        self.assertFalse(report["required_ci_producer_apps_verified"])
        self.assertFalse(report["ready_for_explicit_human_merge_decision"])

    def test_missing_producer_metadata_is_blocking(self):
        self.assertFalse(audit(check_runs=[])["ready_for_explicit_human_merge_decision"])

    def test_wrong_app_pinned_in_protection_is_blocking(self):
        policy = {**PROTECTION, "required_status_checks": {
            "strict": True, "checks": [{"context": "native-checks", "app_id": 42}],
        }}
        self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_wrong_commit_check_run_is_blocking(self):
        run = {**audit_default_check_run(), "head_sha": "c" * 40}
        self.assertFalse(audit(check_runs=[run])["ready_for_explicit_human_merge_decision"])

    def test_comment_after_approval_preserves_approval(self):
        comment = {**HUMAN_REVIEW[0], "state": "COMMENTED"}
        self.assertEqual(
            independent_approvals([HUMAN_REVIEW[0], comment], "a" * 40, "GrimClawBot"),
            ["independentreviewer"],
        )
        self.assertTrue(audit(reviews=[HUMAN_REVIEW[0], comment])[
            "ready_for_explicit_human_merge_decision"
        ])

    def test_green_unrelated_job_is_not_a_required_native_job(self):
        item = pr(statusCheckRollup=[{"name": "CodeRabbit", "conclusion": "SUCCESS"}])
        result = audit(item)
        self.assertEqual(result["missing_required_check_names"], ["native-checks"])
        self.assertFalse(result["ci_complete_and_successful"])
        self.assertFalse(result["ready_for_explicit_human_merge_decision"])

    def test_required_check_cannot_be_neutral_or_skipped(self):
        for status in ("NEUTRAL", "SKIPPED", "CANCELLED", ""):
            with self.subTest(status=status):
                item = pr(statusCheckRollup=[
                    {
                        "name": "native-checks", "conclusion": status,
                        "status": "COMPLETED", "detailsUrl": DEFAULT_RUN_URL,
                    },
                    {"name": "CodeRabbit", "conclusion": "SUCCESS"},
                ])
                self.assertFalse(audit(item)["ready_for_explicit_human_merge_decision"])

    def test_same_sha_other_pr_check_does_not_block_current_pass(self):
        old = {
            **audit_default_check_run(),
            "pull_requests": [{"number": 144}],
            "details_url": "https://github.com/example/old/job/2",
            "conclusion": "failure",
        }
        current = audit_default_check_run()
        item = pr(statusCheckRollup=[
            {
                "name": "native-checks", "status": "COMPLETED",
                "conclusion": "FAILURE", "detailsUrl": old["details_url"],
            },
            {
                "name": "native-checks", "status": "COMPLETED",
                "conclusion": "SUCCESS", "detailsUrl": current["details_url"],
            },
        ])
        result = audit(item, check_runs=[old, current])
        self.assertTrue(result["required_ci_producer_apps_verified"])
        self.assertTrue(result["ready_for_explicit_human_merge_decision"])

    def test_same_sha_other_pr_success_cannot_hide_pending_target_ci(self):
        other = {
            **audit_default_check_run(),
            "pull_requests": [{"number": 144}],
            "details_url": "https://github.com/example/old/job/2",
        }
        pending = {
            **audit_default_check_run(),
            "status": "in_progress", "conclusion": None,
        }
        item = pr(statusCheckRollup=[
            {
                "name": "native-checks", "status": "COMPLETED",
                "conclusion": "SUCCESS", "detailsUrl": other["details_url"],
            },
            {
                "name": "native-checks", "status": "IN_PROGRESS",
                "conclusion": "", "detailsUrl": pending["details_url"],
            },
        ])
        self.assertFalse(audit(item, check_runs=[other, pending])[
            "ready_for_explicit_human_merge_decision"
        ])

    def test_same_pr_duplicate_ci_or_missing_provenance_fails_closed(self):
        good = audit_default_check_run()
        scenarios = [
            [good, good],
            [{**good, "pull_requests": [{"number": 144}]}],
            [{**good, "pull_requests": []}],
            [{**good, "details_url": "https://github.com/example/unmatched"}],
            [{**good, "app": {"id": 999}}],
        ]
        for runs in scenarios:
            with self.subTest(runs=runs):
                self.assertFalse(audit(check_runs=runs)[
                    "ready_for_explicit_human_merge_decision"
                ])

    def test_duplicate_required_context_is_not_trusted(self):
        item = pr(statusCheckRollup=[
            {"name": "native-checks", "conclusion": "SUCCESS",
             "status": "COMPLETED", "detailsUrl": DEFAULT_RUN_URL},
            {"name": "native-checks", "conclusion": "FAILURE",
             "status": "COMPLETED", "detailsUrl": DEFAULT_RUN_URL},
        ])
        self.assertFalse(audit(item)["ready_for_explicit_human_merge_decision"])

    def test_multiple_required_names_must_all_pass(self):
        policy = {**PROTECTION, "required_status_checks": {
            "strict": True, "contexts": ["native-checks", "integration-check"],
            "checks": [
                {"context": "native-checks", "app_id": 15368},
                {"context": "integration-check", "app_id": 15368},
            ],
        }}
        item = pr(statusCheckRollup=[{"name": "native-checks", "conclusion": "SUCCESS"}])
        result = audit(item, policy=policy)
        self.assertEqual(result["missing_required_check_names"], ["integration-check"])
        self.assertFalse(result["ready_for_explicit_human_merge_decision"])

    def test_protection_admin_bypass_is_a_blocker(self):
        policy = {**PROTECTION, "enforce_admins": {"enabled": False}}
        self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_force_push_or_deletion_are_blockers(self):
        for field in ("allow_force_pushes", "allow_deletions"):
            with self.subTest(field=field):
                policy = {**PROTECTION, field: {"enabled": True}}
                self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_stale_or_self_push_approval_allowed_is_blocker(self):
        for field in ("dismiss_stale_reviews", "require_last_push_approval"):
            with self.subTest(field=field):
                policy = {**PROTECTION, "required_pull_request_reviews": {
                    **PROTECTION["required_pull_request_reviews"], field: False,
                }}
                self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_required_checks_must_be_strict(self):
        policy = {**PROTECTION, "required_status_checks": {
            "strict": False, "contexts": ["native-checks"],
        }}
        self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_true_boolean_review_count_is_not_an_integer_approval(self):
        policy = {**PROTECTION, "required_pull_request_reviews": {
            **PROTECTION["required_pull_request_reviews"],
            "required_approving_review_count": True,
        }}
        self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_draft_and_bot_comment_only_are_not_approvals(self):
        result = audit(pr(isDraft=True, reviewDecision=""))
        self.assertFalse(result["pr_approved"])
        self.assertTrue(result["pr_draft"])
        self.assertFalse(result["ready_for_explicit_human_merge_decision"])

    def test_unfinished_check_with_empty_conclusion_is_pending(self):
        item = pr(statusCheckRollup=[
            {"name": "native-checks", "conclusion": "", "status": "IN_PROGRESS",
             "detailsUrl": DEFAULT_RUN_URL}
        ])
        self.assertFalse(audit(item)["ci_complete_and_successful"])

    def test_red_check_blocks_even_approved_pr(self):
        item = pr(statusCheckRollup=[{
            "name": "native-checks", "conclusion": "FAILURE",
            "status": "COMPLETED", "detailsUrl": DEFAULT_RUN_URL,
        }])
        self.assertFalse(audit(item)["ready_for_explicit_human_merge_decision"])

    def test_sha_mismatch_blocks(self):
        self.assertFalse(audit(pr(headRefOid="b" * 40))["github_head_matches_local_git"])

    def test_missing_sha_blocks(self):
        self.assertFalse(audit(pr(headRefOid=None))["ready_for_explicit_human_merge_decision"])

    def test_wrong_branch_or_base_blocks(self):
        self.assertFalse(audit(pr(baseRefName="other"))["ready_for_explicit_human_merge_decision"])
        self.assertFalse(audit(pr(headRefName="unreviewed"))["ready_for_explicit_human_merge_decision"])

    def test_virtual_merge_conflicts_block(self):
        self.assertFalse(audit(virtual_merge_clean=False)["ready_for_explicit_human_merge_decision"])

    def test_outdated_main_ancestor_blocks(self):
        self.assertFalse(audit(git_ancestor=False)["ready_for_explicit_human_merge_decision"])

    def test_unknown_mergeability_blocks(self):
        self.assertFalse(audit(pr(mergeable="UNKNOWN"))["ready_for_explicit_human_merge_decision"])


if __name__ == "__main__":
    unittest.main()
