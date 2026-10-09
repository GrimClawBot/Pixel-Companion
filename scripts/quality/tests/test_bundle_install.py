"""Behavioral checks for app-bundle replacement and macOS package generation."""
import os
import plistlib
import time
from contextlib import redirect_stderr
from io import StringIO
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

    def test_cleanup_failure_after_success_does_not_fail_install(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            output = parent / "Pixel Companion.app"
            output.mkdir()
            (output / "version").write_text("old")
            stage = parent / "stage"
            staged = stage / "New.app"
            staged.mkdir(parents=True)
            (staged / "version").write_text("updated")
            stderr = StringIO()
            with mock.patch("scripts.quality.install_bundle.shutil.rmtree", side_effect=OSError("busy")):
                with redirect_stderr(stderr):
                    install(staged, output, output)
            self.assertEqual((output / "version").read_text(), "updated")
            self.assertEqual((stage / "Previous.app" / "version").read_text(), "old")
            self.assertIn("WARNING: new app installed", stderr.getvalue())

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
            import hashlib
            physical_output = output.parent.resolve() / output.name
            digest = hashlib.sha256(str(physical_output).encode()).hexdigest()[:32]
            lock = physical_output.parent / (".pixel-companion-" + digest + ".lock")
            lock.mkdir()
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/package_macos.sh"), "--debug", "--output", str(output)],
                cwd=base, capture_output=True, text=True, timeout=15
            )
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("Packaging already in progress", result.stderr)
            self.assertTrue(lock.is_dir())
            self.assertFalse(output.exists())

    def test_symlinked_app_destination_is_rejected_without_build(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            real_app = base / "existing.app"
            real_app.mkdir()
            (real_app / "marker").write_text("do not alter")
            alias_app = base / "alias.app"
            alias_app.symlink_to(real_app, target_is_directory=True)
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/package_macos.sh"), "--debug",
                 "--output", str(alias_app)],
                capture_output=True, text=True, timeout=15,
            )
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("Refusing symlinked .app destination", result.stderr)
            self.assertEqual((real_app / "marker").read_text(), "do not alter")
            self.assertTrue(alias_app.is_symlink())
            self.assertFalse(list(base.glob(".pixel-companion-*.lock")))

    def test_parent_symlink_alias_blocks_concurrent_packaging(self):
        # Stub only swift: the first invocation holds the lock at its build
        # step, while the aliased second invocation must stop BEFORE build.
        # Neither attempt can install or overwrite any .app bundle.
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            real = base / "actual"
            real.mkdir()
            alias = base / "alias"
            alias.symlink_to(real, target_is_directory=True)
            stub_dir = base / "bin"
            stub_dir.mkdir()
            started = base / "started"
            release = base / "release"
            stub = stub_dir / "swift"
            stub.write_text(
                "#!/bin/sh\n"
                "printf ready > \"$PC_PACKAGE_STARTED\"\n"
                "while [ ! -f \"$PC_PACKAGE_RELEASE\" ]; do sleep 0.05; done\n"
                "exit 87\n"
            )
            stub.chmod(0o755)
            env = {
                **os.environ, "PATH": str(stub_dir) + os.pathsep + os.environ["PATH"],
                "PC_PACKAGE_STARTED": str(started),
                "PC_PACKAGE_RELEASE": str(release),
            }
            output = real / "unique.app"
            first = subprocess.Popen(
                ["bash", str(ROOT / "scripts/package_macos.sh"), "--debug",
                 "--output", str(output)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, env=env,
            )
            try:
                for _ in range(200):
                    if started.exists() or first.poll() is not None:
                        break
                    time.sleep(0.05)
                self.assertTrue(started.exists(), "first packager did not reach lock-protected build")
                contender = subprocess.run(
                    ["bash", str(ROOT / "scripts/package_macos.sh"), "--debug",
                     "--output", str(alias / output.name)],
                    capture_output=True, text=True, timeout=15, env=env,
                )
                self.assertEqual(contender.returncode, 2, contender.stdout + contender.stderr)
                self.assertIn("Packaging already in progress", contender.stderr)
                self.assertFalse(output.exists())
            finally:
                release.touch()
                try:
                    first.communicate(timeout=15)
                except subprocess.TimeoutExpired:
                    first.kill()
                    first.communicate(timeout=5)
            self.assertNotEqual(first.returncode, 0, "test stub must stop before installation")
            self.assertFalse(list(real.glob(".pixel-companion-*.lock")))
            self.assertFalse(output.exists())

    def test_long_valid_app_name_has_short_lock_name(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            # A 250-byte UTF-8 filename is valid on APFS, unlike filename+lock suffix.
            output = base / ("a" * 246 + ".app")
            cmd = ["bash", str(ROOT / "scripts/package_macos.sh"), "--debug", "--output", str(output)]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((output / "Contents/MacOS/PixelCompanion").is_file())
            self.assertFalse(list(base.glob(".pixel-companion-*.lock")))

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
