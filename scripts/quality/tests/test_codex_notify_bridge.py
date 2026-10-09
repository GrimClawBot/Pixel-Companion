"""Codex privacy-scrubbed completion hook tests: no transcript storage."""
import json
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest

from scripts.codex_notify_bridge import (
    EVENT_FILENAME, MAX_INPUT_BYTES, scrub_notification, write_marker,
)


class CodexNotifyBridgeTests(unittest.TestCase):
    def setUp(self):
        self.timestamp = "2026-10-08T10:00:00Z"

    def test_removes_every_sensitive_field(self):
        incoming = {
            "type": "agent-turn-complete",
            "thread-id": "secret-thread-123",
            "turn-id": "private-turn",
            "cwd": "/private/path",
            "input-messages": ["my password is do-not-store"],
            "last-assistant-message": "confidential answer",
            "other": {"nested": "secret"},
        }
        marker = scrub_notification(json.dumps(incoming), self.timestamp)
        self.assertEqual(marker, {
            "schemaVersion": 1,
            "event": "agent-turn-complete",
            "lastCompletedAt": self.timestamp,
        })
        encoded = json.dumps(marker)
        for secret in ["secret", "password", "path", "confidential", "thread", "private-turn"]:
            self.assertNotIn(secret, encoded)

    def test_rejects_other_events_and_invalid_json_without_writing(self):
        self.assertIsNone(scrub_notification('{"type":"approval-requested"}', self.timestamp))
        self.assertIsNone(scrub_notification("{}", self.timestamp))
        self.assertIsNone(scrub_notification("not JSON", self.timestamp))
        self.assertIsNone(scrub_notification("[]" , self.timestamp))
        self.assertIsNone(scrub_notification("x" * (MAX_INPUT_BYTES + 1), self.timestamp))

    def test_file_is_mode_0600_atomic_and_contains_no_raw_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = scrub_notification(
                '{"type":"agent-turn-complete","input-messages":["SECRET-TEXT"]}',
                self.timestamp,
            )
            output = write_marker(root, marker)
            self.assertEqual(output.name, EVENT_FILENAME)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(output.read_text()), marker)
            self.assertNotIn("SECRET-TEXT", output.read_text())
            self.assertEqual(list(root.iterdir()), [output])

    def test_replaces_symlink_without_touching_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "personal-secret"
            target.write_text("untouched")
            (root / EVENT_FILENAME).symlink_to(target)
            write_marker(root, {
                "schemaVersion": 1, "event": "agent-turn-complete",
                "lastCompletedAt": self.timestamp,
            })
            self.assertEqual(target.read_text(), "untouched")
            self.assertFalse((root / EVENT_FILENAME).is_symlink())

    def test_actual_documented_argv_entrypoint_discards_private_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            incoming = json.dumps({
                "type": "agent-turn-complete",
                "thread-id": "PRIVATE-THREAD",
                "input-messages": ["PRIVATE-PROMPT"],
                "last-assistant-message": "PRIVATE-ANSWER",
            })
            script = Path(__file__).resolve().parents[2] / "codex_notify_bridge.py"
            call = subprocess.run(
                [sys.executable, str(script), "--directory", str(root), incoming],
                capture_output=True, text=True, check=True,
            )
            self.assertEqual(call.stdout, "")
            self.assertEqual(call.stderr, "")
            marker = (root / EVENT_FILENAME).read_text()
            self.assertNotIn("PRIVATE", marker)
            self.assertEqual(json.loads(marker)["event"], "agent-turn-complete")

    def test_rejects_missing_or_symlink_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            link = root / "symlink"
            link.symlink_to(root, target_is_directory=True)
            with self.assertRaises(ValueError):
                write_marker(link, {})
            with self.assertRaises(ValueError):
                write_marker(root / "missing", {})


if __name__ == "__main__":
    unittest.main()
