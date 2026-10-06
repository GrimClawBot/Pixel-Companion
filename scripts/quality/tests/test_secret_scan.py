import unittest

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


if __name__ == "__main__":
    unittest.main()
