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
            self.assertIn("PixelCompanion.xcodeproj/project.pbxproj declares remote Swift packages", errors[0])

            lock_rel = (
                "PixelCompanion.xcodeproj/project.xcworkspace/"
                "xcshareddata/swiftpm/Package.resolved"
            )
            self.assertTrue(vc.is_xcode_lockfile(lock_rel))
            self.assertEqual([], vc.lockfile_errors(root, tracked | {lock_rel}))

    def test_unrelated_xcode_lockfile_does_not_satisfy_another_project(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            projects = []
            for name in ("AppA", "AppB"):
                rel = f"{name}.xcodeproj/project.pbxproj"
                path = root / rel
                path.parent.mkdir(parents=True)
                path.write_text(
                    "/* Begin XCRemoteSwiftPackageReference section */\n"
                    "repositoryURL = https://example.invalid/repo.git;\n"
                )
                projects.append(rel)

            app_a_lock = (
                "AppA.xcodeproj/project.xcworkspace/"
                "xcshareddata/swiftpm/Package.resolved"
            )
            errors = vc.lockfile_errors(root, set(projects) | {app_a_lock})
            self.assertEqual(1, len(errors))
            self.assertIn("AppB.xcodeproj/project.pbxproj", errors[0])

    def test_workspace_lockfile_satisfies_only_its_member_project(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            project_rel = "App.xcodeproj/project.pbxproj"
            project = root / project_rel
            project.parent.mkdir(parents=True)
            project.write_text(
                "/* Begin XCRemoteSwiftPackageReference section */\n"
                "repositoryURL = https://example.invalid/repo.git;\n"
            )
            workspace_rel = "Product.xcworkspace/contents.xcworkspacedata"
            workspace = root / workspace_rel
            workspace.parent.mkdir(parents=True)
            workspace.write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<Workspace version="1.0">\n'
                '  <FileRef location="group:App.xcodeproj"></FileRef>\n'
                '</Workspace>\n'
            )
            lock_rel = (
                "Product.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            )
            tracked = {project_rel, workspace_rel, lock_rel}
            self.assertEqual([], vc.lockfile_errors(root, tracked))

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
