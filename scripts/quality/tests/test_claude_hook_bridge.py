"""Privacy and no-decision tests for optional Claude Code hook bridge."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from scripts.claude_hook_bridge import (
    EVENT_FILENAME, EVENTS, MAX_INPUT_BYTES, scrub_notification, write_marker,
)


class ClaudeHookBridgeTests(unittest.TestCase):
    def setUp(self):
        self.timestamp = "2026-10-08T10:00:00Z"

    def test_exact_event_allowlist_and_minimal_result(self):
        for event in EVENTS:
            value = scrub_notification(
                json.dumps({"hook_event_name": event}).encode(), self.timestamp
            )
            self.assertEqual(value, {
                "schemaVersion": 1, "event": event, "observedAt": self.timestamp
            })

    def test_private_payload_fields_are_never_persisted(self):
        incoming = {
            "hook_event_name": "UserPromptSubmit",
            "prompt": "PRIVATE-PROMPT",
            "session_id": "PRIVATE-SESSION",
            "transcript_path": "/PRIVATE/PATH",
            "cwd": "/PRIVATE/WORKSPACE",
            "response": "PRIVATE-RESPONSE",
            "error": "PRIVATE-ERROR",
            "nested": {"secret": "PRIVATE-KEY"},
        }
        marker = scrub_notification(json.dumps(incoming).encode(), self.timestamp)
        self.assertNotIn("PRIVATE", json.dumps(marker))
        self.assertEqual(set(marker), {"schemaVersion", "event", "observedAt"})

    def test_malformed_unsupported_and_oversized_are_ignored(self):
        for value in [
            b"", b"not JSON", b"[]", b"null", b"{}",
            b'{"hook_event_name":"PermissionRequest"}',
            b'{"hook_event_name":"PreToolUse"}',
            b'{"hook_event_name":42}',
            b"x" * (MAX_INPUT_BYTES + 1),
        ]:
            self.assertIsNone(scrub_notification(value, self.timestamp))

    def test_atomic_mode_0600_and_no_stale_temp_files(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            marker = {"schemaVersion": 1, "event": "Stop", "observedAt": self.timestamp}
            output = write_marker(folder, marker)
            self.assertEqual(output.name, EVENT_FILENAME)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(output.read_text()), marker)
            self.assertEqual(list(folder.iterdir()), [output])

    def test_existing_symlink_is_replaced_not_followed(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            secret = folder / "secret.txt"
            secret.write_text("must survive")
            output = folder / EVENT_FILENAME
            output.symlink_to(secret)
            write_marker(folder, {
                "schemaVersion": 1, "event": "SessionEnd",
                "observedAt": self.timestamp,
            })
            self.assertEqual(secret.read_text(), "must survive")
            self.assertFalse(output.is_symlink())

    def test_symlink_or_missing_directory_not_accepted(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            link = folder / "alias"
            link.symlink_to(folder, target_is_directory=True)
            for bad in [link, folder / "missing"]:
                with self.assertRaises(ValueError):
                    write_marker(bad, {})

    def test_actual_stdin_process_is_silent_and_scrubbed(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            script = Path(__file__).resolve().parents[2] / "claude_hook_bridge.py"
            raw = json.dumps({
                "hook_event_name": "Stop",
                "session_id": "PRIVATE-ID",
                "transcript_path": "/PRIVATE-PATH",
                "last_assistant_message": "PRIVATE-ANSWER",
            })
            result = subprocess.run(
                [sys.executable, str(script), "--directory", str(folder)],
                input=raw, text=True, capture_output=True, check=True,
            )
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")
            output = (folder / EVENT_FILENAME).read_text()
            self.assertNotIn("PRIVATE", output)
            self.assertEqual(json.loads(output)["event"], "Stop")

    def test_unsupported_event_does_not_change_previous_marker(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            script = Path(__file__).resolve().parents[2] / "claude_hook_bridge.py"
            marker = folder / EVENT_FILENAME
            marker.write_text("UNCHANGED")
            result = subprocess.run(
                [sys.executable, str(script), "--directory", str(folder)],
                input='{"hook_event_name":"PreToolUse"}', text=True,
                capture_output=True, check=True,
            )
            self.assertEqual((result.stdout, result.stderr), ("", ""))
            self.assertEqual(marker.read_text(), "UNCHANGED")


if __name__ == "__main__":
    unittest.main()
