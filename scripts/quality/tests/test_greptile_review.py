import unittest

from scripts.quality import greptile_review as gr


def finding(severity):
    return gr.Finding(severity=severity, file="a.swift", line=1, title="t")


class ParseFindingsTests(unittest.TestCase):
    def test_parses_fenced_json(self):
        msg = 'Here you go:\n```json\n[{"severity": "Major", "file": "A.swift", "line": "12", "title": "Leak"}]\n```'
        (f,) = gr.parse_findings(msg)
        self.assertEqual(("major", "A.swift", 12, "Leak"), (f.severity, f.file, f.line, f.title))
        self.assertTrue(f.blocking)

    def test_empty_array_is_clean(self):
        self.assertEqual([], gr.parse_findings("```json\n[]\n```"))

    def test_unknown_severity_escalates_to_blocker(self):
        (f,) = gr.parse_findings('[{"severity": "critical", "title": "x"}]')
        self.assertEqual("blocker", f.severity)

    def test_unparseable_response_raises(self):
        for msg in ["Looks good to me!", "[not json]", '{"severity": "nit"}', '["looks fine"]']:
            with self.assertRaises(ValueError, msg=msg):
                gr.parse_findings(msg)


class DecideTests(unittest.TestCase):
    def test_blocking_findings_block_even_when_sensitive(self):
        self.assertEqual(("blocked", gr.EXIT_BLOCKED), gr.decide([finding("blocker")], ["auth"]))
        self.assertEqual(("blocked", gr.EXIT_BLOCKED), gr.decide([finding("nit"), finding("major")], []))

    def test_sensitive_never_auto_approves(self):
        self.assertEqual(("human_review_required", gr.EXIT_HUMAN), gr.decide([finding("minor")], ["ci: .github/x"]))

    def test_clean_non_sensitive_passes(self):
        self.assertEqual(("pass", gr.EXIT_PASS), gr.decide([finding("minor"), finding("nit")], []))


class ClassifySensitiveTests(unittest.TestCase):
    def test_sensitive_paths(self):
        reasons = gr.classify_sensitive(
            [".github/workflows/quality.yml", "Sources/App/AuthService.swift", "App/App.entitlements", "Package.resolved"],
            "",
        )
        self.assertIn("ci: .github/workflows/quality.yml", reasons)
        self.assertIn("auth: Sources/App/AuthService.swift", reasons)
        self.assertIn("permissions: App/App.entitlements", reasons)
        self.assertIn("dependencies: Package.resolved", reasons)

    def test_public_api_and_secret_content(self):
        diff = "+++ b/Sources/Lib/View.swift\n+    public func render() {}\n-@MainActor open class Foo {}\n+SecItemAdd(q, nil)\n"
        self.assertEqual(["public-api", "secrets"], gr.classify_sensitive(["Sources/Lib/View.swift"], diff))

    def test_multiline_public_api_change_uses_unchanged_hunk_context(self):
        diff = (
            "--- a/Sources/Lib/API.swift\n"
            "+++ b/Sources/Lib/API.swift\n"
            "@@ -1,4 +1,4 @@\n"
            " public func render(\n"
            "-    width: Int,\n"
            "+    width: Double,\n"
            "     height: Int\n"
            " ) -> View\n"
        )
        self.assertEqual(["public-api"], gr.classify_sensitive(["Sources/Lib/API.swift"], diff))

    def test_login_and_session_changes_require_human_review(self):
        diff = "+++ b/Sources/App/LoginCoordinator.swift\n+    func signIn() { session = newSession }\n"
        reasons = gr.classify_sensitive(["Sources/App/LoginCoordinator.swift"], diff)
        self.assertTrue(any(reason.startswith("auth:") for reason in reasons))
        self.assertIn("auth", reasons)

    def test_allow_marker_pattern_is_registered(self):
        patterns = [pattern.pattern for pattern, _ in gr.SENSITIVE_CONTENT]
        self.assertTrue(any("allow" in pattern for pattern in patterns))

    def test_plain_change_is_not_sensitive(self):
        diff = "+++ b/Sources/App/NotchView.swift\n+    let width: CGFloat = 200\n context line public\n"
        self.assertEqual([], gr.classify_sensitive(["Sources/App/NotchView.swift"], diff))


if __name__ == "__main__":
    unittest.main()
