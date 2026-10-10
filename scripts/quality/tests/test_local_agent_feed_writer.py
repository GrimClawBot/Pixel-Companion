"""Tests for the user-run local agent status publisher."""
import json
import tempfile
import unittest
from pathlib import Path

from scripts.local_agent_feed_writer import build_feed, publish


class LocalAgentFeedWriterTests(unittest.TestCase):
    def test_provider_and_multiple_rows(self):
        feed = build_feed(
            [("codex", "c1", "running", "Codex"),
             ("claude-code", "a1", "waiting", "Claude")],
            "2026-10-08T10:00:00Z",
        )
        self.assertEqual(feed["schemaVersion"], 1)
        self.assertEqual(len(feed["sessions"]), 2)
        self.assertNotIn("prompt", feed["sessions"][0])

    def test_rejects_untrusted_status_and_id(self):
        for spec in [
            ("codex", "../../secret", "running", "Codex"),
            ("claude-code", "x", "approved", "Claude"),
            ("unknown", "x", "running", "Unknown"),
            ("codex", "x", "running", "Bad\nLabel"),
        ]:
            with self.assertRaises(ValueError):
                build_feed([spec], "2026-10-08T10:00:00Z")

    def test_rejects_duplicate_and_over_limit(self):
        one = ("codex", "c1", "running", "Codex")
        with self.assertRaises(ValueError):
            build_feed([one, one], "2026-10-08T10:00:00Z")
        with self.assertRaises(ValueError):
            build_feed(
                [("codex", f"id-{i}", "idle", "Codex") for i in range(13)],
                "2026-10-08T10:00:00Z",
            )

    def test_writes_atomic_restricted_json(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "status.json"
            payload = build_feed(
                [("hermes", "h1", "idle", "Hermes")], "2026-10-08T10:00:00Z"
            )
            publish(output, payload)
            self.assertEqual(json.loads(output.read_text()), payload)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(Path(directory).iterdir()), [output])

    def test_symlink_destination_is_replaced_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = root / "source"
            secret.write_text("unchanged")
            target = root / "status.json"
            target.symlink_to(secret)
            publish(target, build_feed([], "2026-10-08T10:00:00Z"))
            self.assertEqual(secret.read_text(), "unchanged")
            self.assertFalse(target.is_symlink())


if __name__ == "__main__":
    unittest.main()
