"""Existing user Codex notifier must never be discarded by Pixel Companion."""
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest

from scripts.codex_notify_fanout import dispatch, load_previous_command


class Completed:
    returncode = 0


class CodexNotifyFanoutTests(unittest.TestCase):
    def test_dispatch_delivers_same_private_argv_to_original_and_scrubbed_pixel(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            called = []
            raw = json.dumps({
                "type": "agent-turn-complete", "input-messages": ["SENSITIVE-INPUT"],
                "thread-id": "SENSITIVE-THREAD",
            })
            prior = ["/bin/true", "turn-ended"]
            def executor(args, *, timeout, check):
                called.append(args)
                self.assertEqual(timeout, 30)
                self.assertFalse(check)
                return Completed()
            result = dispatch(prior, raw, folder, executor=executor)
            self.assertEqual(result, (True, True))
            self.assertEqual(called, [prior + [raw]])
            output = folder / "pixel-companion-codex-turn.json"
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
            written = output.read_text()
            self.assertNotIn("SENSITIVE-", written)
            self.assertEqual(json.loads(written)["event"], "agent-turn-complete")

    def test_existing_notifier_called_even_if_pixel_directory_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            called = []
            def executor(args, **_kwargs):
                called.append(args)
                return Completed()
            result = dispatch(
                ["/bin/true"], '{"type":"agent-turn-complete"}',
                Path(directory) / "nonexistent", executor=executor,
            )
            self.assertEqual(result, (True, False))
            self.assertEqual(len(called), 1)

    def test_no_prior_command_never_executes_unrelated_program(self):
        with tempfile.TemporaryDirectory() as directory:
            raw = '{"type":"agent-turn-complete"}'
            result = dispatch(None, raw, Path(directory),
                              executor=lambda *_args, **_kw: self.fail("unexpected execute"))
            self.assertEqual(result, (False, True))

    def test_load_private_previous_command_file(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "original.json"
            file.write_text(json.dumps(["/usr/bin/true", "turn-ended"]))
            file.chmod(0o600)
            self.assertEqual(load_previous_command(file), ["/usr/bin/true", "turn-ended"])
            file.chmod(0o644)
            self.assertIsNone(load_previous_command(file))

    def test_original_command_file_symlink_denied(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "original.json"
            link = Path(directory) / "link.json"
            file.write_text(json.dumps(["/bin/true"]))
            file.chmod(0o600)
            link.symlink_to(file)
            self.assertIsNone(load_previous_command(link))

    def test_oversize_private_event_does_not_forward(self):
        with tempfile.TemporaryDirectory() as directory:
            raw = '{"type":"agent-turn-complete","text":"' + "x" * 262_144 + '"}'
            self.assertEqual(
                dispatch(["/bin/true"], raw, Path(directory),
                         executor=lambda *_a, **_kw: self.fail("unexpected")),
                (False, False)
            )


if __name__ == "__main__":
    unittest.main()
