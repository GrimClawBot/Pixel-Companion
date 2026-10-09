"""Provider hook setup preserves existing configurations and their handlers."""
import json
import unittest
from scripts.ops.connect_pixel_agent_hooks import prepare_codex, prepare_claude

class HookConnectorInstallerTests(unittest.TestCase):
    def test_codex_existing_notification_preserved(self):
        raw = b'notify = ["/Applications/SkyClient", "turn-ended"]\nmodel = "example"\n[projects."/repo"]\ntrust_level = "trusted"\n'
        prior, updated = prepare_codex(raw)
        self.assertEqual(prior, ["/Applications/SkyClient", "turn-ended"])
        self.assertIn(b"codex_notify_fanout.py", updated)
        self.assertIn(b'model = "example"', updated)
        self.assertIn(b'[projects."/repo"]', updated)

    def test_codex_missing_notify_fails(self):
        with self.assertRaises(ValueError):
            prepare_codex(b'model = "example"\n')

    def test_codex_nested_fanout_refused(self):
        _, wrapped = prepare_codex(b'notify = ["/Applications/SkyClient", "turn-ended"]\n')
        with self.assertRaises(ValueError):
            prepare_codex(wrapped)

    def test_claude_merges_without_discarding_existing_hooks_or_settings(self):
        old = {
            "model": "existing", "permissions": {"allow": ["Read"]},
            "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/bin/true"}]}]},
        }
        updated = json.loads(prepare_claude(json.dumps(old).encode()))
        self.assertEqual(updated["model"], "existing")
        self.assertEqual(updated["permissions"], old["permissions"])
        self.assertEqual(updated["hooks"]["Stop"][0], old["hooks"]["Stop"][0])
        self.assertEqual(len(updated["hooks"]["Stop"]), 2)

    def test_claude_merger_is_idempotent(self):
        first = prepare_claude(b'{"custom":true}')
        second = prepare_claude(first)
        self.assertEqual(json.loads(first), json.loads(second))
        for event in ("SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"):
            self.assertEqual(len(json.loads(second)["hooks"][event]), 1)

    def test_invalid_claude_existing_handler_fails_closed(self):
        with self.assertRaises(ValueError):
            prepare_claude(b'{"hooks":{"Stop":"not-a-list"}}')

if __name__ == "__main__":
    unittest.main()
