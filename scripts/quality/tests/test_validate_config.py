import json
import plistlib
import tempfile
import unittest
from pathlib import Path

from scripts.quality import validate_config as vc


class ValidateFileTests(unittest.TestCase):
    def test_accepts_valid_json_and_plist(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            config = root / "greptile.json"
            config.write_text(json.dumps({"ok": True}))
            plist = root / "Info.plist"
            with plist.open("wb") as fh:
                plistlib.dump({"CFBundleName": "Pixel Companion"}, fh)
            self.assertIsNone(vc.validate_file(config))
            self.assertIsNone(vc.validate_file(plist))

    def test_rejects_invalid_json_and_plist(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            config = root / "broken.json"
            config.write_text("{")
            plist = root / "Info.plist"
            plist.write_bytes(b"not a plist")
            self.assertIsNotNone(vc.validate_file(config))
            self.assertIsNotNone(vc.validate_file(plist))


class LockfileTests(unittest.TestCase):
    def test_root_remote_dependency_requires_committed_lockfile(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "Package.swift").write_text(
                '.package(url: "https://example.invalid/repo.git", from: "1.0.0")\n'
            )
            (root / "Package.resolved").write_text("{}")
            errors = vc.lockfile_errors(root, {"Package.swift"})
            self.assertEqual(1, len(errors))
            self.assertIn("Package.resolved is not committed", errors[0])
            self.assertEqual([], vc.lockfile_errors(root, {"Package.swift", "Package.resolved"}))

    def test_xcode_remote_package_requires_committed_xcode_lockfile(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            pbx_rel = "PixelCompanion.xcodeproj/project.pbxproj"
            pbx = root / pbx_rel
            pbx.parent.mkdir(parents=True)
            pbx.write_text(
                "/* Begin XCRemoteSwiftPackageReference section */\n"
                "repositoryURL = https://example.invalid/repo.git;\n"
            )
            tracked = {pbx_rel}
            errors = vc.lockfile_errors(root, tracked)
            self.assertEqual(1, len(errors))
            self.assertIn("Xcode project declares remote Swift packages", errors[0])

            lock_rel = (
                "PixelCompanion.xcodeproj/project.xcworkspace/"
                "xcshareddata/swiftpm/Package.resolved"
            )
            self.assertTrue(vc.is_xcode_lockfile(lock_rel))
            self.assertEqual([], vc.lockfile_errors(root, tracked | {lock_rel}))

    def test_xcode_project_without_remote_packages_needs_no_lockfile(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            pbx_rel = "PixelCompanion.xcodeproj/project.pbxproj"
            pbx = root / pbx_rel
            pbx.parent.mkdir(parents=True)
            pbx.write_text("PBXProject = {};\n")
            self.assertEqual([], vc.lockfile_errors(root, {pbx_rel}))


if __name__ == "__main__":
    unittest.main()
