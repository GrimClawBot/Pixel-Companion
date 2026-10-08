import unittest
from unittest.mock import patch
from subprocess import CompletedProcess
from scripts.quality.premerge_audit import analyze, audit, classify_parallel_heads


def pr(number, head, base, *, draft=False, review="APPROVED",
       conclusion="SUCCESS", mergeable="MERGEABLE"):
    return {
        "number": number, "headRefName": head, "baseRefName": base,
        "isDraft": draft, "reviewDecision": review,
        "mergeable": mergeable,
        "statusCheckRollup": [{"name": "native-checks", "conclusion": conclusion}],
    }


class PremergeAuditTests(unittest.TestCase):
    def test_clean_linear_reviewed_chain_can_be_handed_for_human_merge(self):
        report = analyze([pr(1, "integration", "main"),
                          pr(2, "feature", "integration")], "feature")
        self.assertEqual(report["tip_chain_pr_numbers_newest_first"], [2, 1])
        self.assertEqual(report["base_root_pr_numbers"], [1])
        self.assertTrue(report["candidate_ready_for_human_merge_decision"])
        self.assertFalse(report["merge_allowed_by_this_audit"])

    def test_parallel_direct_main_roots_are_release_blockers(self):
        items = [pr(1, "integration", "main"), pr(2, "feature", "integration"),
                 pr(3, "legacy", "main")]
        report = analyze(items, "feature")
        self.assertEqual(report["base_root_pr_numbers"], [1, 3])
        self.assertEqual(report["outside_tip_chain_pr_numbers"], [3])
        self.assertFalse(report["candidate_ready_for_human_merge_decision"])

    def test_draft_and_unapproved_chain_never_ready(self):
        report = analyze([pr(1, "a", "main", draft=True, review="")], "a")
        self.assertIn(1, report["draft_pr_numbers"])
        self.assertIn(1, report["unapproved_pr_numbers"])
        self.assertFalse(report["candidate_ready_for_human_merge_decision"])

    def test_ci_failure_and_pending_are_not_success(self):
        items = [pr(1, "a", "main", conclusion="FAILURE"),
                 pr(2, "b", "a", conclusion=None)]
        result = analyze(items, "b")
        self.assertEqual(result["failing_ci_pr_numbers"], [1])
        self.assertEqual(result["pending_ci_pr_numbers"], [2])
        self.assertEqual(result["passing_ci_pr_count"], 0)

    def test_invalid_mergeability_is_blocking(self):
        result = analyze(
            [pr(1, "a", "main", mergeable="CONFLICTING"),
             pr(2, "b", "a", mergeable="UNKNOWN")], "b"
        )
        self.assertEqual(result["merge_conflict_pr_numbers"], [1])
        self.assertEqual(result["unknown_mergeability_pr_numbers"], [2])

    def test_cycle_cannot_be_misreported_as_main_ancestor(self):
        result = analyze([pr(1, "a", "b"), pr(2, "b", "a")], "a")
        self.assertTrue(result["cyclic_tip_chain"])
        self.assertFalse(result["tip_reaches_base"])
        self.assertFalse(result["candidate_ready_for_human_merge_decision"])

    def test_dangling_branch_is_reported(self):
        result = analyze([pr(1, "a", "missing")], "a")
        self.assertEqual(result["dangling_base_pr_numbers"], [1])
        self.assertFalse(result["candidate_ready_for_human_merge_decision"])

    def test_duplicate_identifiers_are_reported(self):
        result = analyze([pr(1, "a", "main"), pr(2, "a", "main")], "a")
        self.assertEqual(result["duplicate_head_branches"], ["a"])
        self.assertFalse(result["candidate_ready_for_human_merge_decision"])

    def test_virtual_merge_probe_failure_blocks_even_approved_chain(self):
        result = audit([pr(1, "a", "main")], "a", "main", check_git=False)
        self.assertEqual(result["git_readonly_probe"], {"not_run": True})
        self.assertTrue(result["candidate_ready_for_human_merge_decision"])

    def test_already_included_legacy_pr_is_not_an_extra_code_delta(self):
        prs = [
            pr(1, "integration", "main"),
            pr(2, "feature", "integration"),
            pr(3, "old", "main"),
        ]
        def fake_run(args):
            if args[:2] == ["git", "rev-parse"]:
                return CompletedProcess(args, 0, "sha", "")
            if args[:3] == ["git", "merge-base", "--is-ancestor"]:
                return CompletedProcess(args, 0, "", "")
            raise AssertionError("unexpected command")
        with patch("scripts.quality.premerge_audit.run_command", side_effect=fake_run):
            result = classify_parallel_heads(prs, "feature", [3])
        self.assertEqual(result["already_in_candidate"], [3])
        self.assertEqual(result["divergent_changes"], [])
        self.assertEqual(result["unresolved_git_ref"], [])

    def test_separate_changes_are_not_labeled_already_included(self):
        prs = [pr(1, "candidate", "main"), pr(2, "other", "main")]
        def fake_run(args):
            if args[:2] == ["git", "rev-parse"]:
                return CompletedProcess(args, 0, "sha", "")
            if args[:3] == ["git", "merge-base", "--is-ancestor"]:
                return CompletedProcess(args, 1, "", "")
            raise AssertionError("unexpected command")
        with patch("scripts.quality.premerge_audit.run_command", side_effect=fake_run):
            result = classify_parallel_heads(prs, "candidate", [2])
        self.assertEqual(result["divergent_changes"], [2])

    def test_missing_git_ref_is_not_trusted_as_included(self):
        prs = [pr(1, "candidate", "main"), pr(2, "legacy", "main")]
        with patch(
            "scripts.quality.premerge_audit.run_command",
            return_value=CompletedProcess([], 1, "", "")
        ):
            result = classify_parallel_heads(prs, "candidate", [2])
        self.assertEqual(result["unresolved_git_ref"], [2])
        self.assertEqual(result["already_in_candidate"], [])

    def test_unknown_status_check_rollup_never_counts_as_pass(self):
        item = pr(1, "a", "main")
        item["statusCheckRollup"] = [{"name": "native-checks", "conclusion": None}]
        result = analyze([item], "a")
        self.assertEqual(result["pending_ci_pr_numbers"], [1])


if __name__ == "__main__":
    unittest.main()
