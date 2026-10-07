"""Atomically replace a staged .app, retaining the last good bundle on failure."""
from pathlib import Path
import shutil
import sys


def install(staged: Path, destination: Path, default_destination: Path) -> None:
    if not staged.is_dir() or destination.suffix != ".app":
        raise ValueError("Expected a staged application and an .app destination")
    if destination.exists() and destination != default_destination:
        raise FileExistsError("Refusing to replace an existing custom output")
    if staged.stat().st_dev != destination.parent.stat().st_dev:
        raise OSError("Staging and destination must share a filesystem")

    if not destination.exists():
        staged.rename(destination)
        return

    backup = staged.parent / "Previous.app"
    if backup.exists():
        raise FileExistsError("Refusing to overwrite an existing rollback copy")
    destination.rename(backup)
    try:
        staged.rename(destination)
    except Exception:
        backup.rename(destination)
        raise
    # Successful installation: the newly installed app is now in place.
    shutil.rmtree(backup)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: install_bundle.py STAGED_APP DEST_APP DEFAULT_APP")
    install(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
