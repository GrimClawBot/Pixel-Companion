"""Old QA cleanup must be reversible, scoped and gated by a valid signed QA78."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "retire_old_qa_macos.sh"
BUNDLE_ID = "io.github.grimclawbot.PixelCompanion"


@unittest.skipUnless(sys.platform == "darwin", "Needs native macOS code signing")
class RetireOldQAMacTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        (self.home / "Applications").mkdir()
        (self.home / ".Trash").mkdir()
        self.env = dict(os.environ, HOME=str(self.home))

    def qa_app(self, number, marker=None, identifier=BUNDLE_ID):
        name = f"Pixel Companion QA Update {number}.app"
        app = self.home / "Applications" / name
        contents = app / "Contents"
        binary_dir = contents / "MacOS"
        binary_dir.mkdir(parents=True)
        shutil.copy2("/usr/bin/true", binary_dir / "PixelCompanion")
        with (contents / "Info.plist").open("wb") as output:
            plistlib.dump({
                "CFBundleName": "PixelCompanion",
                "CFBundleExecutable": "PixelCompanion",
                "CFBundleIdentifier": identifier,
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": str(number),
                "CFBundleShortVersionString": "0.1.0",
                "PCQAUpdateNumber": str(number if marker is None else marker)
            }, output)
        subprocess.run(
            ["codesign", "--force", "--sign", "-", "--timestamp=none", str(app)],
            check=True, capture_output=True, text=True
        )
        return app

    def run_script(self, mode):
        return subprocess.run(
            ["bash", str(SCRIPT), mode],
            env=self.env, text=True, capture_output=True, check=False
        )

    def test_missing_new_bundle_prevents_all_moves(self):
        previous = self.qa_app(74)
        res = self.run_script("--apply")
        self.assertEqual(res.returncode, 2, res.stderr)
        self.assertIn("Nothing moved", res.stderr)
        self.assertTrue(previous.is_dir())
        self.assertEqual(list((self.home / ".Trash").iterdir()), [])

    def test_invalid_new_bundle_marker_prevents_all_moves(self):
        previous = self.qa_app(74)
        self.qa_app(78, marker=77)
        res = self.run_script("--apply")
        self.assertEqual(res.returncode, 2, res.stderr)
        self.assertTrue(previous.is_dir())
        self.assertEqual(list((self.home / ".Trash").iterdir()), [])

    def test_dry_run_preserves_old_and_does_not_create_trash_folder(self):
        current = self.qa_app(78)
        previous = self.qa_app(74)
        res = self.run_script("--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn(f"WOULD_TRASH={previous}", res.stdout)
        self.assertIn("DRY_RUN_ONLY=yes", res.stdout)
        self.assertTrue(previous.is_dir())
        self.assertTrue(current.is_dir())
        self.assertEqual(list((self.home / ".Trash").iterdir()), [])

    def test_apply_moves_only_signed_old_qa_with_correct_bundle_id(self):
        current = self.qa_app(78)
        previous = self.qa_app(74)
        wrong_identity = self.qa_app(72, identifier="example.other.application")
        res = self.run_script("--apply")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("OLDER_QA_MOVED=1", res.stdout)
        self.assertFalse(previous.exists())
        self.assertTrue(wrong_identity.is_dir())
        self.assertTrue(current.is_dir())
        folders = list((self.home / ".Trash").iterdir())
        self.assertEqual(len(folders), 1)
        self.assertTrue((folders[0] / previous.name).is_dir())
        self.assertFalse((folders[0] / current.name).exists())

    def test_symlink_to_old_bundle_is_never_moved(self):
        current = self.qa_app(78)
        actual = self.qa_app(74)
        actual.rename(self.home / "Backup QA 74.app")
        old_symlink = self.home / "Applications" / actual.name
        old_symlink.symlink_to(self.home / "Backup QA 74.app")
        res = self.run_script("--apply")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("SKIP_UNVERIFIED=", res.stdout)
        self.assertTrue(old_symlink.is_symlink())
        self.assertTrue(current.is_dir())
        self.assertEqual(list((self.home / ".Trash").iterdir()), [])


class RetireOldQASourceTests(unittest.TestCase):
    def test_script_parses_and_help_does_not_mutate(self):
        subprocess.run(["bash", "-n", str(SCRIPT)], check=True)
        help_text = subprocess.check_output(["bash", str(SCRIPT), "--help"], text=True)
        self.assertIn("--dry-run|--apply", help_text)

    def test_targets_are_explicit_and_cleanup_is_reversible(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("for QA in 61 72 74 76 77", source)
        self.assertIn("Pixel Companion QA Update 78.app", source)
        self.assertIn("PCQAUpdateNumber", source)
        self.assertIn("CFBundleIdentifier", source)
        self.assertIn("codesign --verify --strict", source)
        self.assertIn('! verify_qa "$LATEST" 78', source)
        self.assertIn('"$MODE" == "--apply"', source)
        self.assertIn('"$TRASH/PixelCompanion-OldQA.XXXXXXXX"', source)
        self.assertNotIn("rm -rf", source)
        self.assertNotIn("killall", source)
        self.assertNotIn("pkill", source)
        self.assertNotIn("defaults delete", source)
        self.assertNotIn("SMAppService", source)

    def test_no_macos_performs_no_cleanup(self):
        if sys.platform == "darwin":
            self.skipTest("macOS-positive cases above")
        with tempfile.TemporaryDirectory() as tmp:
            proc = subprocess.run(
                ["bash", str(SCRIPT), "--apply"], text=True, capture_output=True,
                env={**os.environ, "HOME": tmp}, check=False
            )
            self.assertEqual(proc.returncode, 2)
            self.assertFalse((Path(tmp) / "Applications").exists())


if __name__ == "__main__":
    unittest.main()
