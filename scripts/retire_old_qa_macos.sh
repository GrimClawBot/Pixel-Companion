#!/usr/bin/env bash
# Only retire verified owner-local QA app bundles after QA78 has been accepted.
# Old builds go to the macOS Trash; never recursively delete.
set -euo pipefail
usage() {
  echo "Usage: scripts/retire_old_qa_macos.sh [--dry-run|--apply]"
}
MODE="--dry-run"
while (( $# )); do
  case "$1" in
    --dry-run|--apply) MODE="$1"; shift ;;
    --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Only the owner's Mac can retire its QA apps." >&2
  exit 2
fi
for cmd in codesign pgrep mktemp; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 2; }
done
[[ -x /usr/libexec/PlistBuddy ]] || { echo "Missing PlistBuddy" >&2; exit 2; }

APP_DIR="$HOME/Applications"
TRASH="$HOME/.Trash"
LATEST="$APP_DIR/Pixel Companion QA Update 78.app"
BUNDLE_ID="io.github.grimclawbot.PixelCompanion"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null
}
verify_qa() {
  local app="$1"
  local number="$2"
  [[ -d "$app" && ! -L "$app" ]] || return 1
  [[ ! -L "$app/Contents" && ! -L "$app/Contents/Info.plist" ]] || return 1
  [[ "$(plist_value "$app" PCQAUpdateNumber)" == "$number" ]] || return 1
  [[ "$(plist_value "$app" CFBundleVersion)" == "$number" ]] || return 1
  [[ "$(plist_value "$app" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || return 1
  [[ "$(plist_value "$app" CFBundleExecutable)" == "PixelCompanion" ]] || return 1
  codesign --verify --strict "$app" >/dev/null 2>&1
}
is_running() {
  # Skip any app whose exact executable path appears in the process list.
  pgrep -f "$1/Contents/MacOS/PixelCompanion" >/dev/null 2>&1
}

if [[ -L "$APP_DIR" || ! -d "$APP_DIR" || -L "$LATEST" ]] || ! verify_qa "$LATEST" 78; then
  echo "The signed QA78 app at its expected location is missing or invalid. Nothing moved." >&2
  exit 2
fi
if [[ "$MODE" == "--apply" && ( -L "$TRASH" || ! -d "$TRASH" ) ]]; then
  echo "Owner's Trash is missing or unsafe. Nothing moved." >&2
  exit 2
fi

FOUND=0
MOVED=0
DEST=""
for QA in 61 72 74 76 77; do
  OLD="$APP_DIR/Pixel Companion QA Update $QA.app"
  if [[ ! -e "$OLD" && ! -L "$OLD" ]]; then continue; fi
  if ! verify_qa "$OLD" "$QA"; then
    printf "SKIP_UNVERIFIED=%s\n" "$OLD"
    continue
  fi
  if is_running "$OLD"; then
    printf "SKIP_RUNNING=%s\n" "$OLD"
    continue
  fi
  FOUND=$((FOUND + 1))
  if [[ "$MODE" == "--dry-run" ]]; then
    printf "WOULD_TRASH=%s\n" "$OLD"
    continue
  fi
  if [[ -z "$DEST" ]]; then
    DEST="$(mktemp -d "$TRASH/PixelCompanion-OldQA.XXXXXXXX")"
  fi
  mv "$OLD" "$DEST/"
  MOVED=$((MOVED + 1))
  printf "MOVED_TO_TRASH=%s\n" "$DEST/Pixel Companion QA Update $QA.app"
done

printf "VERIFIED_QA78=%s\n" "$LATEST"
printf "OLDER_QA_CANDIDATES=%s\n" "$FOUND"
if [[ "$MODE" == "--apply" ]]; then
  printf "OLDER_QA_MOVED=%s\n" "$MOVED"
  printf "TRASH_RECOVERY_FOLDER=%s\n" "$DEST"
else
  echo "DRY_RUN_ONLY=yes"
  echo "After visually accepting QA78, run again with --apply."
fi
