import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.quality import secret_scan as ss

# Fixtures are assembled at runtime so this file never contains a literal secret.
GITHUB = "gh" + "p_" + "A1b2C3d4" * 5
AWS = "AK" + "IA" + "ABCDEFGHIJKLMNOP"
ANTHROPIC = "sk-" + "ant-" + "api03-" + "x" * 40
PEM = "-----BEGIN " + "RSA PRIVATE KEY-----"
GENERIC = "api" + "Key = " + '"Zq8vL2mN4pR7sT1uW3xY"'


class ScanLineTests(unittest.TestCase):
    def rules(self, text):
        return {f.rule for f in ss.scan_line("f.swift", 1, text)}

    def test_detects_known_token_shapes(self):
        self.assertIn("github-token", self.rules(f'let t = "{GITHUB}"'))
        self.assertIn("aws-access-key-id", self.rules(AWS))
        self.assertIn("anthropic-key", self.rules(ANTHROPIC))
        self.assertIn("private-key", self.rules(PEM))

    def test_detects_generic_assignment(self):
        self.assertIn("generic-assignment", self.rules(GENERIC))

    def test_ignores_placeholders_and_env_lookups(self):
        self.assertEqual(set(), self.rules('let apiKey = ProcessInfo.processInfo.environment["API_KEY"]'))
        self.assertEqual(set(), self.rules('password = "${PASSWORD}"'))
        self.assertEqual(set(), self.rules('token = "<your-token-here>"'))

    def test_allow_marker_suppresses(self):
        self.assertEqual(set(), self.rules(f"{GITHUB}  // {ss.ALLOW_MARKER}"))

    def test_finding_render_never_contains_value(self):
        (finding,) = [f for f in ss.scan_line("a.txt", 3, GITHUB) if f.rule == "github-token"]
        self.assertNotIn(GITHUB, finding.render())
        self.assertEqual("a.txt:3: github-token", finding.render())


class ForbiddenPathTests(unittest.TestCase):
    def test_forbidden(self):
        for path in [".env", "app/.env", ".env.local", "certs/dev.p12", "x.mobileprovision", "keys/id_rsa"]:
            self.assertTrue(ss.forbidden_path(path), path)

    def test_allowed(self):
        for path in [".env.example", "app/.env.example", "Sources/App/Environment.swift", "README.md"]:
            self.assertFalse(ss.forbidden_path(path), path)


class DiffParsingTests(unittest.TestCase):
    def test_tracks_new_line_numbers_and_paths(self):
        diff = "\n".join(
            [
                "diff --git a/x.swift b/x.swift",
                "--- a/x.swift",
                "+++ b/x.swift",
                "@@ -1,0 +5,2 @@",
                "+first",
                "+second",
                "diff --git a/gone.swift b/gone.swift",
                "--- a/gone.swift",
                "+++ /dev/null",
                "@@ -1 +0,0 @@",
                "-removed",
            ]
        )
        self.assertEqual([("x.swift", 5, "first"), ("x.swift", 6, "second")], ss.parse_added_lines(diff))


class HistoryRangeTests(unittest.TestCase):
    def git(self, root, *args):
        return subprocess.run(
            ["git", *args], cwd=root, check=True, capture_output=True, text=True
        ).stdout.strip()

    def commit(self, root, message):
        self.git(root, "add", "-A")
        self.git(root, "commit", "-m", message)

    def test_detects_secret_added_then_removed_from_branch_history(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.git(root, "init", "-q")
            self.git(root, "config", "user.email", "quality@example.invalid")
            self.git(root, "config", "user.name", "Quality Test")
            (root / "fixture.txt").write_text("safe\n")
            self.commit(root, "base")
            base = self.git(root, "rev-parse", "HEAD")

            (root / "fixture.txt").write_text(f"{GITHUB}\n")
            self.commit(root, "introduce credential")
            (root / "fixture.txt").write_text("safe again\n")
            self.commit(root, "remove credential")

            findings = ss.scan_range(root, f"{base}...HEAD")
            self.assertTrue(
                any(f.rule == "github-token" and f.path == "fixture.txt" for f in findings)
            )

    def test_detects_forbidden_file_added_then_removed(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.git(root, "init", "-q")
            self.git(root, "config", "user.email", "quality@example.invalid")
            self.git(root, "config", "user.name", "Quality Test")
            (root / "README.md").write_text("base\n")
            self.commit(root, "base")
            base = self.git(root, "rev-parse", "HEAD")

            (root / ".env").write_text("placeholder=true\n")
            self.commit(root, "add forbidden file")
            (root / ".env").unlink()
            self.commit(root, "remove forbidden file")

            findings = ss.scan_range(root, f"{base}...HEAD")
            self.assertTrue(any(f.rule == "forbidden-file" and f.path == ".env" for f in findings))


if __name__ == "__main__":
    unittest.main()
