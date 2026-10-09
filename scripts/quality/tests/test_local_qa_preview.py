"""Checks that the local QA preview is safe and executable without network delivery."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "qa_preview_macos.sh"
PACKAGER = ROOT / "scripts" / "package_macos.sh"


class LocalQAPreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SCRIPT.read_text(encoding="utf-8")

    def test_bash_parse_and_help_do_not_require_macos_or_build(self):
        subprocess.run(["bash", "-n", str(SCRIPT)], check=True)
        completed = subprocess.run(
            ["bash", str(SCRIPT), "--help"],
            capture_output=True, text=True, check=True
        )
        self.assertIn("--no-open", completed.stdout)

    def test_qa_marker_is_inserted_before_signed_packaging(self):
        src = self.source
        marker = src.index("Add :PCQAUpdateNumber string $QA")
        packaging = src.index('"$ROOT/scripts/package_macos.sh" --release')
        validate = src.index('codesign --verify --strict')
        extract = src.index("Print :PCQAUpdateNumber")
        launch = src.index('open -n "$APP"')
        self.assertLess(marker, packaging)
        self.assertLess(packaging, validate)
        self.assertLess(validate, extract)
        self.assertLess(extract, launch)
        self.assertIn('if [[ "$BUILT_MARKER" != "$QA" ]]', src)

    def test_existing_preview_never_overwritten_and_qa61_preserved(self):
        src = self.source
        self.assertIn('APP="$HOME/Applications/Pixel Companion QA Update 72.app"', src)
        self.assertIn('if [[ -e "$APP" || -L "$APP" ]]', src)
        self.assertIn("refusing", src.lower())
        self.assertNotIn("rm -rf", src)
        self.assertNotIn("pkill", src)
        self.assertNotIn("killall", src)
        self.assertNotIn("SMAppService", src)
        self.assertNotIn("defaults delete", src)
        self.assertIn("OLD_QA61_UNTOUCHED=yes", src)

    def test_private_plist_is_the_only_metadata_input_to_signing(self):
        src = self.source
        self.assertIn('cp "$PLIST" "$TEMP_PLIST"', src)
        self.assertIn('trap cleanup_plist EXIT', src)
        self.assertIn('Add :PCQAUpdateNumber string $QA" "$TEMP_PLIST"', src)
        self.assertIn('--info-plist "$TEMP_PLIST"', src)
        self.assertNotIn('Add :PCQAUpdateNumber string $QA" "$PLIST"', src)
        self.assertNotIn('cp "$TEMP_PLIST" "$PLIST"', src)
        package = PACKAGER.read_text(encoding="utf-8")
        self.assertIn('--info-plist)', package)
        self.assertIn('plutil -lint "$INFO_PLIST"', package)
        self.assertIn('cp "$INFO_PLIST" "$APP/Contents/Info.plist"', package)
        self.assertNotIn('cp packaging/Info.plist "$APP/Contents/Info.plist"', package)
        subprocess.run(["bash", "-n", str(PACKAGER)], check=True)

    def test_installer_refuses_dirty_checkout_and_supports_non_launch_mode(self):
        src = self.source
        self.assertIn('git diff --quiet', src)
        self.assertIn('git diff --cached --quiet', src)
        self.assertIn('git status --porcelain --untracked-files=all -- Sources Tests scripts packaging Package.swift', src)
        self.assertIn('git ls-files --others --ignored --exclude-standard -- Sources Tests packaging', src)
        self.assertIn("--no-open", src)
        self.assertIn('if [[ "$OPEN_APP" == 1 ]]', src)
        self.assertIn('git rev-parse HEAD', src)

    def test_untracked_and_ignored_swift_sources_fail_clean_input_checks(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            sources = root / "Sources"
            sources.mkdir()
            unexpected = sources / "Injected.swift"
            unexpected.write_text("print(\"unexpected\")", encoding="utf-8")
            found = subprocess.check_output(
                ["git", "status", "--porcelain", "--untracked-files=all",
                 "--", "Sources", "Tests", "scripts", "packaging", "Package.swift"],
                cwd=root, text=True
            )
            self.assertIn("Injected.swift", found)
            (root / ".gitignore").write_text("Sources/Injected.swift\n", encoding="utf-8")
            ignored = subprocess.check_output(
                ["git", "ls-files", "--others", "--ignored", "--exclude-standard",
                 "--", "Sources", "Tests", "packaging"],
                cwd=root, text=True
            )
            self.assertIn("Sources/Injected.swift", ignored)


if __name__ == "__main__":
    unittest.main()
