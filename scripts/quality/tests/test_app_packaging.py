"""Static safety and compatibility checks for macOS app bundling."""
import plistlib
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

class AppPackagingTests(unittest.TestCase):
    def test_bundle_metadata(self):
        with (ROOT / "packaging/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["CFBundleIdentifier"], "io.github.grimclawbot.PixelCompanion")
        self.assertEqual(info["CFBundleExecutable"], "PixelCompanion")
        self.assertEqual(info["CFBundlePackageType"], "APPL")
        self.assertTrue(info["LSUIElement"])
        self.assertEqual(info["LSMinimumSystemVersion"], "14.0")
        self.assertEqual(info["CFBundleIconFile"], "PixelCompanion")

    def test_bundle_script_is_valid_bash(self):
        subprocess.run(
            ["bash", "-n", str(ROOT / "scripts/package_macos.sh")],
            check=True,
            capture_output=True,
        )

    def test_bundle_script_does_not_auto_publish(self):
        content = (ROOT / "scripts/package_macos.sh").read_text()
        self.assertIn("codesign --verify", content)
        self.assertNotIn("notarytool submit", content)
        self.assertNotIn("gh release create", content)
        self.assertIn("swift build", content)

if __name__ == "__main__":
    unittest.main()
