#!/usr/bin/env python3
"""Opt-in, reversible integration for *this Mac's* Codex and Claude hooks.

No secrets printed, no model turns, no agent control. Run --apply only after
human authorization. Validate before writing and preserve exact backups.
Existing Codex notify handler receives its original argv via fanout.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
from datetime import datetime, timezone
# Keep these limits in exact parity with codex_notify_fanout.py.
# The script must work by absolute path from outside the repository root.
MAX_ORIGINAL_ARGS = 32
MAX_ORIGINAL_COMMAND_BYTES = 16_384

try:
    import tomllib
except ImportError:
    import toml as tomllib

HOME = Path.home()
REPO = Path(__file__).resolve().parents[2]
SUPPORT = HOME / "Library" / "Application Support" / "Pixel Companion"
FOLDERS = SUPPORT / "Agent Events"
CODEX_FOLDER = FOLDERS / "Codex"
CLAUDE_FOLDER = FOLDERS / "Claude Code"
BACKUPS = SUPPORT / "Hook Config Backups"
ORIGINAL_NOTIFY = SUPPORT / "original-codex-notify.json"
CODEX_CONFIG = HOME / ".codex" / "config.toml"
CLAUDE_CONFIG = HOME / ".claude" / "settings.json"
FANOUT = REPO / "scripts" / "codex_notify_fanout.py"
CLAUDE_BRIDGE = REPO / "scripts" / "claude_hook_bridge.py"
CLAUDE_EVENTS = ("SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd")


def ensure_safe_file(path: Path) -> bytes:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError("Expected owned regular provider config")
    if info.st_size > 512_000:
        raise ValueError("Oversized provider config")
    return path.read_bytes()


def require_existing_scripts() -> None:
    for script in (FANOUT, REPO / "scripts" / "codex_notify_bridge.py", CLAUDE_BRIDGE):
        info = script.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError("Untrusted hook bridge")


def mkdir_private(folder: Path) -> None:
    if not folder.exists():
        folder.mkdir(mode=0o700)
    info = folder.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError("Expected owned private folder")
    if stat.S_IMODE(info.st_mode) & 0o077:
        raise ValueError("Existing folder does not have user-only permissions")


def save_atomic(path: Path, data: bytes, mode: int = 0o600) -> None:
    handle, name = tempfile.mkstemp(prefix=".pixel-agent-", dir=path.parent)
    try:
        with os.fdopen(handle, "wb") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def replace_if_exact(path: Path, expected: bytes, updated: bytes) -> None:
    """Refuse to replace provider bytes that changed since our last snapshot.

    This check is not a filesystem-wide compare-and-swap: other provider
    processes may write concurrently. Revalidate just before each individual
    write and avoid overwriting a detected edit during rollback.
    """
    if ensure_safe_file(path) != expected:
        raise ValueError("Provider settings changed during transaction")
    save_atomic(path, updated)


def prepare_codex(blob: bytes) -> tuple[list[str], bytes]:
    content = blob.decode("utf-8")
    config = tomllib.loads(content)
    command = config.get("notify")
    if (not isinstance(command, list) or
            not (1 <= len(command) <= MAX_ORIGINAL_ARGS) or
            not all(isinstance(arg, str) and 0 < len(arg) <= 4096 for arg in command) or
            not Path(command[0]).is_absolute() or
            len(json.dumps(command).encode("utf-8")) > MAX_ORIGINAL_COMMAND_BYTES):
        raise ValueError("Existing Codex notification exceeds dispatcher's strict limits")
    if str(FANOUT) in command:
        raise ValueError("Pixel fanout already installed; refusing recursive nesting")

    # Only replace the exact TOP LEVEL notify array; preserve every other
    # config line verbatim, including comments, profiles and model settings.
    lines = content.splitlines(keepends=True)
    begin = [i for i, line in enumerate(lines) if re.match(r"^notify\s*=\s*\[", line)]
    if len(begin) != 1:
        raise ValueError("Cannot identify unique top-level Codex notify array")
    start = begin[0]
    if re.search(r"\]\s*(?:#.*)?$", lines[start]):
        end = start
    else:
        end = next(
            (i for i in range(start + 1, len(lines)) if re.match(r"^\]\s*(?:#.*)?$", lines[i])),
            None
        )
    if end is None:
        raise ValueError("Unterminated Codex notify array")
    only_notify = tomllib.loads("".join(lines[start:end + 1]))
    if only_notify != {"notify": command}:
        raise ValueError("Unsupported complex Codex notify representation")
    new_cmd = [
        "/usr/bin/python3", str(FANOUT),
        "--original-command-file", str(ORIGINAL_NOTIFY),
        "--directory", str(CODEX_FOLDER),
    ]
    new_notify = "notify = " + json.dumps(new_cmd, ensure_ascii=True) + "\n"
    revised = "".join(lines[:start]) + new_notify + "".join(lines[end + 1:])
    parsed = tomllib.loads(revised)
    original_except_notify = dict(config)
    updated_except_notify = dict(parsed)
    original_except_notify.pop("notify", None)
    updated_except_notify.pop("notify", None)
    if original_except_notify != updated_except_notify or parsed.get("notify") != new_cmd:
        raise ValueError("Codex config safety comparison failed")
    return command, revised.encode("utf-8")


def prepare_claude(blob: bytes) -> bytes:
    config = json.loads(blob)
    if not isinstance(config, dict):
        raise ValueError("Invalid Claude settings root")
    hooks = config.get("hooks")
    if hooks is None:
        hooks = {}
        config["hooks"] = hooks
    if not isinstance(hooks, dict):
        raise ValueError("Existing Claude hooks are invalid")
    import shlex
    command = " ".join(shlex.quote(arg) for arg in (
        "/usr/bin/python3", str(CLAUDE_BRIDGE), "--directory", str(CLAUDE_FOLDER)
    ))
    for event in CLAUDE_EVENTS:
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            raise ValueError("Invalid existing Claude hook group")
        # Append, never replace pre-existing matching event hooks.
        if not any(isinstance(group, dict) and any(
            isinstance(hook, dict) and hook.get("command") == command
            for hook in group.get("hooks", []) if isinstance(group.get("hooks", []), list)
        ) for group in groups):
            groups.append({"hooks": [{"type": "command", "command": command}]})
    output = (json.dumps(config, indent=2, ensure_ascii=False) + "\n").encode()
    if json.loads(output) != config:
        raise ValueError("Claude configuration validation failed")
    return output


def run(apply: bool) -> None:
    require_existing_scripts()
    codex_old = ensure_safe_file(CODEX_CONFIG)
    claude_old = ensure_safe_file(CLAUDE_CONFIG)
    original_cmd, codex_new = prepare_codex(codex_old)
    claude_new = prepare_claude(claude_old)
    print("Codex original notify: present; will be preserved through fanout")
    print("Claude lifecycle events: 5 command hook handlers will be added")
    print("Codex/Claude provider configuration backup: required")
    if not apply:
        print("ACTION: DRY RUN; no changes made")
        return

    mkdir_private(SUPPORT)
    mkdir_private(FOLDERS)
    mkdir_private(CODEX_FOLDER)
    mkdir_private(CLAUDE_FOLDER)
    mkdir_private(BACKUPS)
    if ORIGINAL_NOTIFY.exists():
        # Safe retry of a failed, rolled-back activation, never overwrite a
        # different prior notifier record.
        previous = ORIGINAL_NOTIFY.lstat()
        if (not stat.S_ISREG(previous.st_mode)
                or previous.st_uid != os.getuid()
                or stat.S_IMODE(previous.st_mode) != 0o600
                or json.loads(ORIGINAL_NOTIFY.read_bytes()) != original_cmd):
            raise ValueError("Previous notifier record differs; refusing overwrite")
    now = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    archive_codex = BACKUPS / ("codex-" + now + ".toml")
    archive_claude = BACKUPS / ("claude-" + now + ".json")
    previous_codex = sorted(BACKUPS.glob("codex-*.toml"))
    previous_claude = sorted(BACKUPS.glob("claude-*.json"))
    already_backed_up = bool(
        previous_codex and previous_claude
        and previous_codex[-1].read_bytes() == codex_old
        and previous_claude[-1].read_bytes() == claude_old
    )
    if not already_backed_up:
        if archive_codex.exists() or archive_claude.exists():
            raise ValueError("Backup collision")
        save_atomic(archive_codex, codex_old)
        save_atomic(archive_claude, claude_old)
    if not ORIGINAL_NOTIFY.exists():
        save_atomic(ORIGINAL_NOTIFY, json.dumps(original_cmd).encode())
    # Recheck after backups (do not race against user edits).
    if ensure_safe_file(CODEX_CONFIG) != codex_old or ensure_safe_file(CLAUDE_CONFIG) != claude_old:
        raise ValueError("Provider settings changed during preparation")
    # Track only writes completed by this attempt. If any provider/user
    # saves new settings while the installer is running, never overwrite them
    # during rollback. There is no cross-provider lock enforced on external editors.
    written: list[tuple[Path, bytes, bytes]] = []
    try:
        replace_if_exact(CODEX_CONFIG, codex_old, codex_new)
        written.append((CODEX_CONFIG, codex_old, codex_new))
        replace_if_exact(CLAUDE_CONFIG, claude_old, claude_new)
        written.append((CLAUDE_CONFIG, claude_old, claude_new))
        if ensure_safe_file(CODEX_CONFIG) != codex_new:
            raise ValueError("Codex settings changed during post-write validation")
        if ensure_safe_file(CLAUDE_CONFIG) != claude_new:
            raise ValueError("Claude settings changed during post-write validation")
    except Exception:
        # Reverse order and only restore bytes still belonging to *this*
        # transaction. Never clobber an edit from the user or provider.
        # A later retry must re-read and revalidate all existing configs.
        for path, original, installed in reversed(written):
            try:
                if ensure_safe_file(path) == installed:
                    replace_if_exact(path, installed, original)
                else:
                    print("ROLLBACK SKIPPED: provider settings changed externally")
            except Exception:
                # A file can disappear, become unsafe, or change between
                # our two rollback reads. Continue restoring other files;
                # preserve the original transaction error for the caller.
                print("ROLLBACK SKIPPED: provider file changed or is unavailable")
        raise
    print("ACTION: APPLIED; prior Codex notifier preserved")
    print("Claude settings: original unrelated fields preserved")
    print("Private event directories: owner-only")
    print("Full provider live event delivery: requires a genuine user turn")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        run(args.apply)
    except Exception as exc:
        print("INSTALL ABORTED:", type(exc).__name__)
        raise SystemExit(1) from None
