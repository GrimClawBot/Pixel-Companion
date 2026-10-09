"""Checks that the local QA preview is safe and executable without network delivery."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "qa_preview_macos.sh"


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

    def test_plist_restoration_is_installed_before_mutation(self):
        src = self.source
        self.assertIn('trap restore_plist EXIT', src)
        self.assertIn('cp "$TEMP_PLIST" "$PLIST"', src)
        self.assertLess(src.index('trap restore_plist EXIT'), src.index('Add :PCQAUpdateNumber'))

    def test_installer_refuses_dirty_checkout_and_supports_non_launch_mode(self):
        src = self.source
        self.assertIn('git diff --quiet', src)
        self.assertIn('git diff --cached --quiet', src)
        self.assertIn("--no-open", src)
        self.assertIn('if [[ "$OPEN_APP" == 1 ]]', src)
        self.assertIn('git rev-parse HEAD', src)


if __name__ == "__main__":
    unittest.main()
