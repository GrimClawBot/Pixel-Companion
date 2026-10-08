"""Behavioral checks for app-bundle replacement and macOS package generation."""
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.quality.install_bundle import install

ROOT = Path(__file__).resolve().parents[3]


class BundleInstallationTests(unittest.TestCase):
    def test_new_and_default_replacement_preserve_correct_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            output = parent / "Pixel Companion.app"
            first = parent / "first" / "New.app"
            first.mkdir(parents=True)
            (first / "version").write_text("original")
            install(first, output, output)
            self.assertEqual((output / "version").read_text(), "original")

            second = parent / "second" / "New.app"
            second.mkdir(parents=True)
            (second / "version").write_text("updated")
            install(second, output, output)
            self.assertEqual((output / "version").read_text(), "updated")
            self.assertFalse((second.parent / "Previous.app").exists())

    def test_failure_restores_previous_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            output = parent / "Pixel Companion.app"
            output.mkdir()
            (output / "version").write_text("working")
            staged = parent / "stage" / "New.app"
            staged.mkdir(parents=True)
            (staged / "version").write_text("new")
            original_rename = Path.rename

            def renamed(path, destination):
                if path == staged and Path(destination) == output:
                    raise OSError("injected installation failure")
                return original_rename(path, destination)

            with mock.patch.object(Path, "rename", renamed):
                with self.assertRaises(OSError):
                    install(staged, output, output)
            self.assertEqual((output / "version").read_text(), "working")
            self.assertTrue(staged.exists())

    def test_failed_restore_preserves_only_rollback_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            output = parent / "Pixel Companion.app"
            output.mkdir()
            (output / "version").write_text("original")
            staged = parent / "stage" / "New.app"
            staged.mkdir(parents=True)
            (staged / "version").write_text("replacement")
            original_rename = Path.rename

            def interleaved_rename(path, destination):
                if path == staged and Path(destination) == output:
                    # Simulate a non-cooperating writer taking the output path.
                    output.mkdir()
                    (output / "version").write_text("competing")
                    raise OSError("injected staged installation failure")
                if path == staged.parent / "Previous.app" and Path(destination) == output:
                    raise FileExistsError("a different bundle already occupies destination")
                return original_rename(path, destination)

            with mock.patch.object(Path, "rename", interleaved_rename):
                with self.assertRaises(FileExistsError):
                    install(staged, output, output)
            self.assertEqual((output / "version").read_text(), "competing")
            self.assertEqual((staged.parent / "Previous.app" / "version").read_text(), "original")

    def test_custom_existing_output_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            existing = parent / "custom.app"
            existing.mkdir()
            (existing / "marker").write_text("untouched")
            staged = parent / "New.app"
            staged.mkdir()
            with self.assertRaises(FileExistsError):
                install(staged, existing, parent / "Pixel Companion.app")
            self.assertEqual((existing / "marker").read_text(), "untouched")


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("swift"), "macOS toolchain required")
class RealMacOSPackagingTests(unittest.TestCase):
    def test_concurrent_lock_blocks_packaging_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            output = base / "Pixel Companion.app"
            lock = Path(str(output) + ".pixel-companion.lock")
            lock.mkdir()
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/package_macos.sh"), "--debug", "--output", str(output)],
                cwd=base, capture_output=True, text=True, timeout=15
            )
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("Packaging already in progress", result.stderr)
            self.assertTrue(lock.is_dir())
            self.assertFalse(output.exists())

    def test_bundle_signs_and_relative_output_respects_caller(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            relative = "Pixel Companion Smoke.app"
            cmd = ["bash", str(ROOT / "scripts/package_macos.sh"), "--debug", "--output", relative]
            first = subprocess.run(cmd, cwd=base, capture_output=True, text=True, timeout=240)
            self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
            app = base / relative
            self.assertTrue((app / "Contents/MacOS/PixelCompanion").is_file())
            self.assertTrue((app / "Contents/Resources/PixelCompanion.icns").is_file())
            with (app / "Contents/Info.plist").open("rb") as stream:
                metadata = plistlib.load(stream)
            self.assertEqual(metadata["CFBundleIdentifier"], "io.github.grimclawbot.PixelCompanion")
            verified = subprocess.run(
                ["codesign", "--verify", "--strict", str(app)], capture_output=True, text=True
            )
            self.assertEqual(verified.returncode, 0, verified.stderr)

            second = subprocess.run(cmd, cwd=base, capture_output=True, text=True, timeout=15)
            self.assertNotEqual(second.returncode, 0)
            self.assertIn("Refusing to replace", second.stderr)
            self.assertTrue((app / "Contents/MacOS/PixelCompanion").is_file())


if __name__ == "__main__":
    unittest.main()
