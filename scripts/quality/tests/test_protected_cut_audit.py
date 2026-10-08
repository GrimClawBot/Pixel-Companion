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
    "required_pull_request_reviews": {"required_approving_review_count": 1},
    "required_status_checks": {"checks": [{"context": "native-checks"}]},
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

    def test_no_review_requirement_refuses_promotion(self):
        policy = {"required_pull_request_reviews": None,
                  "required_status_checks": {"contexts": ["native-checks"]}}
        self.assertFalse(audit(policy=policy)["ready_for_explicit_human_merge_decision"])

    def test_no_required_ci_refuses_promotion(self):
        policy = {"required_pull_request_reviews": {"required_approving_review_count": 1},
                  "required_status_checks": None}
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
