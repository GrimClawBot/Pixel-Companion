"""Provider hook setup preserves existing configurations and their handlers."""
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
from scripts.ops import connect_pixel_agent_hooks as installer
from scripts.ops.connect_pixel_agent_hooks import prepare_codex, prepare_claude

class HookConnectorInstallerTests(unittest.TestCase):
    def test_codex_existing_notification_preserved(self):
        raw = b'notify = ["/Applications/SkyClient", "turn-ended"]\nmodel = "example"\n[projects."/repo"]\ntrust_level = "trusted"\n'
        prior, updated = prepare_codex(raw)
        self.assertEqual(prior, ["/Applications/SkyClient", "turn-ended"])
        self.assertIn(b"codex_notify_fanout.py", updated)
        self.assertIn(b'model = "example"', updated)
        self.assertIn(b'[projects."/repo"]', updated)

    def test_installer_limits_match_dispatcher_and_cli_imports_outside_repo(self):
        from scripts import codex_notify_fanout
        self.assertEqual(installer.MAX_ORIGINAL_ARGS, codex_notify_fanout.MAX_ORIGINAL_ARGS)
        self.assertEqual(
            installer.MAX_ORIGINAL_COMMAND_BYTES,
            codex_notify_fanout.MAX_ORIGINAL_COMMAND_BYTES
        )
        import subprocess
        result = subprocess.run(
            ["/usr/bin/python3", str(installer.__file__), "--help"],
            cwd=tempfile.gettempdir(), capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--apply", result.stdout)

    def test_dispatcher_command_limits_are_enforced_before_mutation(self):
        cases = [
            ["/bin/true", ""],
            ["/bin/true"] + ["x"] * 32,
            ["/bin/true", "x" * 4096, "y" * 4096, "z" * 4096, "a" * 4096],
        ]
        for command in cases:
            with self.subTest(length=len(command)):
                raw = ("notify = " + json.dumps(command) + "\n").encode()
                with self.assertRaises(ValueError):
                    prepare_codex(raw)

    def test_codex_missing_notify_fails(self):
        with self.assertRaises(ValueError):
            prepare_codex(b'model = "example"\n')

    def test_codex_nested_fanout_refused(self):
        _, wrapped = prepare_codex(b'notify = ["/Applications/SkyClient", "turn-ended"]\n')
        with self.assertRaises(ValueError):
            prepare_codex(wrapped)

    def test_dry_run_preserves_both_provider_configs(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            codex = root / "config.toml"
            claude = root / "settings.json"
            codex_bytes = b'notify = ["/bin/true", "safe"]\nmodel = "existing"\n'
            claude_bytes = b'{"model":"existing"}\n'
            codex.write_bytes(codex_bytes)
            claude.write_bytes(claude_bytes)
            with patch.object(installer, "CODEX_CONFIG", codex), patch.object(
                installer, "CLAUDE_CONFIG", claude
            ), patch.object(installer, "require_existing_scripts"), patch.object(
                installer, "save_atomic", side_effect=AssertionError("dry run wrote")
            ):
                installer.run(False)
            self.assertEqual(codex.read_bytes(), codex_bytes)
            self.assertEqual(claude.read_bytes(), claude_bytes)

    def test_failed_second_provider_write_restores_exact_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            codex = root / "config.toml"
            claude = root / "settings.json"
            support = root / "private-support"
            codex_bytes = b'notify = ["/bin/true", "safe"]\nmodel = "existing"\n'
            claude_bytes = b'{"model":"existing"}\n'
            codex.write_bytes(codex_bytes)
            claude.write_bytes(claude_bytes)
            installer_original_write = installer.save_atomic
            failures = []

            def controlled_write(path, data, mode=0o600):
                if path == claude and data != claude_bytes and not failures:
                    failures.append("injected second provider write failure")
                    raise OSError("test injected write failure")
                return installer_original_write(path, data, mode)

            with patch.object(installer, "CODEX_CONFIG", codex), patch.object(
                installer, "CLAUDE_CONFIG", claude
            ), patch.object(installer, "SUPPORT", support), patch.object(
                installer, "FOLDERS", support / "events"
            ), patch.object(installer, "CODEX_FOLDER", support / "events" / "codex"), patch.object(
                installer, "CLAUDE_FOLDER", support / "events" / "claude"
            ), patch.object(installer, "BACKUPS", support / "backups"), patch.object(
                installer, "ORIGINAL_NOTIFY", support / "original.json"
            ), patch.object(installer, "require_existing_scripts"), patch.object(
                installer, "save_atomic", side_effect=controlled_write
            ):
                with self.assertRaises(OSError):
                    installer.run(True)
            self.assertEqual(len(failures), 1)
            self.assertEqual(codex.read_bytes(), codex_bytes)
            self.assertEqual(claude.read_bytes(), claude_bytes)
            backups = support / "backups"
            self.assertEqual(len(list(backups.glob("codex-*.toml"))), 1)
            self.assertEqual(len(list(backups.glob("claude-*.json"))), 1)
            self.assertEqual(next(backups.glob("codex-*.toml")).read_bytes(), codex_bytes)
            self.assertEqual(next(backups.glob("claude-*.json")).read_bytes(), claude_bytes)
            for path in [codex, claude, *backups.iterdir(), support / "original.json"]:
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

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
