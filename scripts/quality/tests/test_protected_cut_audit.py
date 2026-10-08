"""Integration merge protection gate must fail closed on missing evidence."""
import unittest

from scripts.quality.protected_cut_audit import evaluate_cut


def pr(**overrides):
    result = {
        "number": 51, "baseRefName": "main",
        "headRefName": "integration/pixel-companion-readonly-alpha",
        "headRefOid": "a" * 40,
        "isDraft": False, "reviewDecision": "APPROVED",
        "mergeable": "MERGEABLE",
        "statusCheckRollup": [{"name": "native-checks", "conclusion": "SUCCESS"}],
    }
    result.update(overrides)
    return result


PROTECTION = {
    "required_pull_request_reviews": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews": True,
        "require_last_push_approval": True,
    },
    "required_status_checks": {
        "strict": True, "checks": [{"context": "native-checks"}],
    },
    "enforce_admins": {"enabled": True},
    "allow_force_pushes": {"enabled": False},
    "allow_deletions": {"enabled": False},
}


def audit(item=None, policy=PROTECTION, **overrides):
    defaults = {
        "base": "main",
        "candidate_head": "integration/pixel-companion-readonly-alpha",
        "git_head": "a" * 40,
        "git_ancestor": True,
        "virtual_merge_clean": True,
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
