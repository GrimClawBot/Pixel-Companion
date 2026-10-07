import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/quality.yml"
CHECK_SCRIPT = ROOT / "scripts/quality/check.sh"


class QualityWorkflowTests(unittest.TestCase):
    def test_pull_request_base_ref_is_passed_via_environment(self):
        text = WORKFLOW.read_text()
        self.assertIn("QUALITY_BASE_REF: ${{ github.base_ref || 'main' }}", text)
        self.assertIn('run: scripts/quality/check.sh --base "origin/$QUALITY_BASE_REF"', text)
        self.assertNotIn('run: scripts/quality/check.sh --base "origin/${{', text)


class XcodeContainerSelectionTests(unittest.TestCase):
    def test_workspace_is_preferred_over_project(self):
        text = CHECK_SCRIPT.read_text()
        self.assertIn("XCODE_WORKSPACE=", text)
        self.assertIn("XCODE_PROJECT=", text)
        self.assertIn('if [[ -n "$XCODE_WORKSPACE" ]]; then', text)
        self.assertIn('XCODE_CONTAINER="${XCODE_WORKSPACE%/*}"', text)
        self.assertIn('elif [[ -n "$XCODE_PROJECT" ]]; then', text)
        self.assertIn('XCODE_CONTAINER="${XCODE_PROJECT%/*}"', text)
        self.assertLess(
            text.index('if [[ -n "$XCODE_WORKSPACE" ]]'),
            text.index('elif [[ -n "$XCODE_PROJECT" ]]'),
        )


if __name__ == "__main__":
    unittest.main()
