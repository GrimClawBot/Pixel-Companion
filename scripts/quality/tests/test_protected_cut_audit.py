"""Integration merge protection gate must fail closed on missing evidence."""
import unittest

from scripts.quality.protected_cut_audit import evaluate_cut, independent_approvals


def pr(**overrides):
    result = {
        "number": 51, "baseRefName": "main",
        "headRefName": "integration/pixel-companion-readonly-alpha",
        "headRefOid": "a" * 40, "baseRefOid": "b" * 40,
        "author": {"login": "GrimClawBot"},
        "isDraft": False, "reviewDecision": "APPROVED",
        "mergeable": "MERGEABLE",
        "statusCheckRollup": [{"name": "native-checks", "conclusion": "SUCCESS"}],
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
        "check_runs": [{
            "name": "native-checks", "head_sha": "a" * 40,
            "status": "completed", "conclusion": "success",
            "app": {"id": 15368},
        }],
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
                    {"name": "native-checks", "conclusion": status},
                    {"name": "CodeRabbit", "conclusion": "SUCCESS"},
                ])
                self.assertFalse(audit(item)["ready_for_explicit_human_merge_decision"])

    def test_duplicate_required_context_is_not_trusted(self):
        item = pr(statusCheckRollup=[
            {"name": "native-checks", "conclusion": "SUCCESS"},
            {"name": "native-checks", "conclusion": "FAILURE"},
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
            {"name": "native-checks", "conclusion": "", "status": "IN_PROGRESS"}
        ])
        self.assertFalse(audit(item)["ci_complete_and_successful"])

    def test_red_check_blocks_even_approved_pr(self):
        item = pr(statusCheckRollup=[{"name": "native-checks", "conclusion": "FAILURE"}])
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
