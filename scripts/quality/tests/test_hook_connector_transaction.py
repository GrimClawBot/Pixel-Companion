"""Isolated provider-install transaction tests; never use real user settings."""
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock

from scripts.ops import connect_pixel_agent_hooks as installer
from scripts import codex_notify_fanout as dispatcher


class HookConnectorTransactionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="pc84-hook-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.codex = self.root / "provider-config.toml"
        self.claude = self.root / "provider-settings.json"
        self.codex_blob = b'notify = ["/bin/echo", "original-handler"]\nmodel = "unchanged"\n'
        self.claude_blob = b'{"custom":{"keep":"exact"},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/bin/true"}]}]}}\n'
        self.codex.write_bytes(self.codex_blob)
        self.claude.write_bytes(self.claude_blob)
        self.codex.chmod(0o600)
        self.claude.chmod(0o600)
        support = self.root / "pixel-support"
        self.backups = support / "Hook Config Backups"
        self.original = support / "original-notify.json"
        mapping = {
            "CODEX_CONFIG": self.codex, "CLAUDE_CONFIG": self.claude,
            "SUPPORT": support, "FOLDERS": support / "Agent Events",
            "CODEX_FOLDER": support / "Agent Events" / "Codex",
            "CLAUDE_FOLDER": support / "Agent Events" / "Claude",
            "BACKUPS": self.backups, "ORIGINAL_NOTIFY": self.original,
            "FANOUT": self.root / "safe-fanout.py",
            "CLAUDE_BRIDGE": self.root / "safe-claude.py",
        }
        self.patches = [
            mock.patch.multiple(installer, **mapping),
            mock.patch.object(installer, "require_existing_scripts", return_value=None),
        ]
        for patcher in self.patches:
            patcher.start()
            self.addCleanup(patcher.stop)

    def assert_private(self, file):
        self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o600)

    def test_installer_command_bounds_exactly_match_dispatcher(self):
        self.assertEqual(installer.MAX_ORIGINAL_ARGS, dispatcher.MAX_ORIGINAL_ARGS)
        self.assertEqual(
            installer.MAX_ORIGINAL_COMMAND_BYTES, dispatcher.MAX_ORIGINAL_COMMAND_BYTES
        )
        for command in (
            ["/bin/echo", ""],
            ["/bin/echo"] + ["x"] * dispatcher.MAX_ORIGINAL_ARGS,
            ["/bin/echo"] + ["x" * 4096] * 5,
        ):
            blob = ("notify = " + json.dumps(command) + "\n").encode()
            with self.subTest(length=len(command)):
                with self.assertRaises(ValueError):
                    installer.prepare_codex(blob)
        command, _ = installer.prepare_codex(self.codex_blob)
        self.assertEqual(command, ["/bin/echo", "original-handler"])

    def test_supported_notifier_boundaries_are_replayable_without_loss(self):
        self.original.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        near_limit = ["/bin/echo", "a" * 4096, "b" * 4096, "c" * 4096, "x"]
        to_pad = dispatcher.MAX_ORIGINAL_COMMAND_BYTES - len(
            json.dumps(near_limit).encode("utf-8")
        )
        self.assertTrue(0 <= to_pad < 4096)
        near_limit[-1] += "z" * to_pad
        self.assertEqual(
            len(json.dumps(near_limit).encode("utf-8")),
            dispatcher.MAX_ORIGINAL_COMMAND_BYTES,
        )
        maximum_args = ["/bin/echo"] + ["x"] * 31
        maximum_arg = ["/bin/echo", "q" * 4096]
        for command in (maximum_args, maximum_arg, near_limit):
            with self.subTest(arguments=len(command), bytes=len(json.dumps(command))):
                prior, updated = installer.prepare_codex(
                    ("notify = " + json.dumps(command) + "\n").encode("utf-8")
                )
                self.assertEqual(prior, command)
                self.assertIn(str(installer.FANOUT).encode("utf-8"), updated)
                self.original.write_bytes(json.dumps(command).encode("utf-8"))
                self.original.chmod(0o600)
                self.assertEqual(dispatcher.load_previous_command(self.original), command)

        # One byte past the serialized limit, still within each argv item limit.
        too_long = near_limit.copy()
        too_long[-1] += "z"
        self.assertEqual(len(json.dumps(too_long).encode()), 16_385)
        with self.assertRaises(ValueError):
            installer.prepare_codex(
                ("notify = " + json.dumps(too_long) + "\n").encode("utf-8")
            )
        self.original.write_bytes(json.dumps(too_long).encode("utf-8"))
        self.original.chmod(0o600)
        self.assertIsNone(dispatcher.load_previous_command(self.original))

    def test_dry_run_does_not_touch_configs_create_directories_or_backups(self):
        installer.run(apply=False)
        self.assertEqual(self.codex.read_bytes(), self.codex_blob)
        self.assertEqual(self.claude.read_bytes(), self.claude_blob)
        self.assertFalse(installer.SUPPORT.exists())
        self.assertFalse(installer.BACKUPS.exists())
        self.assertFalse(installer.ORIGINAL_NOTIFY.exists())

    def test_apply_preserves_exact_backups_original_notifier_and_permissions(self):
        installer.run(apply=True)
        backups = list(self.backups.glob("*"))
        self.assertEqual(len(backups), 2)
        self.assertEqual(next(self.backups.glob("codex-*.toml")).read_bytes(), self.codex_blob)
        self.assertEqual(next(self.backups.glob("claude-*.json")).read_bytes(), self.claude_blob)
        for path in backups + [self.codex, self.claude, self.original]:
            self.assert_private(path)
        self.assertEqual(json.loads(self.original.read_bytes()), ["/bin/echo", "original-handler"])
        self.assertEqual(dispatcher.load_previous_command(self.original), ["/bin/echo", "original-handler"])
        self.assertEqual(installer.tomllib.loads(self.codex.read_text())["model"], "unchanged")
        self.assertEqual(json.loads(self.claude.read_bytes())["custom"], {"keep": "exact"})

    def test_second_provider_write_failure_restores_both_exact_originals(self):
        real_save = installer.save_atomic
        failed = False

        def one_failure(path, payload, mode=0o600):
            nonlocal failed
            if path == self.claude and payload != self.claude_blob and not failed:
                failed = True
                raise OSError("simulated second provider write failure")
            return real_save(path, payload, mode=mode)

        with mock.patch.object(installer, "save_atomic", side_effect=one_failure):
            with self.assertRaises(OSError):
                installer.run(apply=True)
        self.assertTrue(failed)
        self.assertEqual(self.codex.read_bytes(), self.codex_blob)
        self.assertEqual(self.claude.read_bytes(), self.claude_blob)
        self.assert_private(self.codex)
        self.assert_private(self.claude)
        self.assertEqual(len(list(self.backups.glob("*"))), 2)

    def test_changed_provider_config_fails_before_replacing_either_config(self):
        real_read = installer.ensure_safe_file
        reads = 0
        def moved_read(path):
            nonlocal reads
            reads += 1
            if reads == 3 and path == self.codex:
                return b"another process changed the provider settings"
            return real_read(path)
        with mock.patch.object(installer, "ensure_safe_file", side_effect=moved_read):
            with self.assertRaises(ValueError):
                installer.run(apply=True)
        self.assertEqual(self.codex.read_bytes(), self.codex_blob)
        self.assertEqual(self.claude.read_bytes(), self.claude_blob)


if __name__ == "__main__":
    unittest.main()
