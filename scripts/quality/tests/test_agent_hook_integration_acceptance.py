"""Exercise the actual optional bridge binaries without executing any model."""
import unittest

from scripts.quality.integration.verify_agent_hook_bridges import run_acceptance


class AgentHookIntegrationAcceptanceTests(unittest.TestCase):
    def test_two_bridges_scrub_payload_and_produce_private_markers(self):
        results = run_acceptance()
        self.assertEqual(results["codex_bridge"], "PASS")
        self.assertEqual(results["claude_bridge"], "PASS")
        self.assertEqual(results["private_payload_scrubbing"], "PASS")
        self.assertEqual(results["restricted_atomic_markers"], "PASS")

    def test_does_not_claim_real_provider_event_delivery(self):
        results = run_acceptance()
        self.assertEqual(results["actual_codex_provider_delivery"], "NOT_TESTED")
        self.assertEqual(results["actual_claude_provider_delivery"], "NOT_TESTED")


if __name__ == "__main__":
    unittest.main()
