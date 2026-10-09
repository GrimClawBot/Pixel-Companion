#!/usr/bin/env bash
# Owner-local disposable QA preview; never modifies an installed app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PLIST="$ROOT/packaging/Info.plist"
QA="72"

usage() {
  echo "Usage: scripts/qa_preview_macos.sh [--qa-number 72|74|76|77|78|80|81|82|83|84|85|86] [--no-open] [--print-plan]"
}
OPEN_APP=1
PRINT_PLAN=0
while (( $# )); do
  case "$1" in
    --no-open) OPEN_APP=0; shift ;;
    --print-plan) PRINT_PLAN=1; shift ;;
    --qa-number) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; QA="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
# Only known, reviewed QA numbers may be bundled; never manufacture release IDs.
case "$QA" in
  72|74|76|77|78|80|81|82|83|84|85|86) ;;
  *) echo "Unsupported QA number: $QA (allowed: 72, 74, 76, 77, 78, 80, 81, 82, 83, 84, 85, 86)" >&2; exit 2 ;;
esac
APP="$HOME/Applications/Pixel Companion QA Update $QA.app"
if [[ "$PRINT_PLAN" == 1 ]]; then
  # Planning is side-effect free and does not claim an app was built or signed.
  printf "PLANNED_QA_NUMBER=%s\nPLANNED_APP=%s\nPLANNED_QA_MARKER=%s\n" "$QA" "$APP" "$QA"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This preview must be built on the owner's Mac." >&2
  exit 2
fi
for cmd in swift git python3 codesign plutil; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 2; }
done
[[ -x /usr/libexec/PlistBuddy ]] || { echo "Missing PlistBuddy" >&2; exit 2; }
cd "$ROOT"
if ! git diff --quiet || ! git diff --cached --quiet || \
   [[ -n "$(git status --porcelain --untracked-files=all -- Sources Tests scripts packaging Package.swift)" ]] || \
   [[ -n "$(git ls-files --others --ignored --exclude-standard -- Sources Tests packaging)" ]]; then
  echo "Refusing changed, untracked or ignored build inputs: use a clean preview clone." >&2
  exit 2
fi

# A custom destination is never overwritten by package_macos.sh.
# Reject unexpected files and dangling symlinks before building.
if [[ -e "$APP" || -L "$APP" ]]; then
  echo "QA$QA already exists; not replacing it: $APP" >&2
  exit 2
fi
SOURCE_SHA="$(git rev-parse HEAD)"
TEMP_PLIST="$(mktemp -t pixel-companion-qa-plist.XXXXXXXX)"
cp "$PLIST" "$TEMP_PLIST"
cleanup_plist() { rm -f "$TEMP_PLIST"; }
trap cleanup_plist EXIT

# QA metadata prevents registration of Launch at Login in this temporary bundle.
/usr/libexec/PlistBuddy -c "Add :PCQAUpdateNumber string $QA" "$TEMP_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Pixel Companion QA Update $QA" "$TEMP_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $QA" "$TEMP_PLIST"
plutil -lint "$TEMP_PLIST"

# Packaging copies this isolated plist; concurrent builds cannot read QA metadata
# from the shared checked-in packaging/Info.plist source file.
"$ROOT/scripts/package_macos.sh" --release --output "$APP" --info-plist "$TEMP_PLIST"
codesign --verify --strict --verbose=2 "$APP"
BUILT_MARKER="$(/usr/libexec/PlistBuddy -c 'Print :PCQAUpdateNumber' "$APP/Contents/Info.plist")"
if [[ "$BUILT_MARKER" != "$QA" ]]; then
  echo "Build is not marked disposable QA$QA: refusing launch" >&2
  exit 1
fi
echo "VERIFIED_QA_NUMBER=$BUILT_MARKER"
echo "SOURCE_SHA=$SOURCE_SHA"
echo "PREVIEW_APP=$APP"
echo "OLDER_QA_BUILDS_UNTOUCHED=yes"
echo "START_AT_LOGIN=disabled_in_QA_build"

# No process termination, replacement, login registration or backend action.
# Quit any other running Pixel Companion QA app in its UI first.
# These disposable QA bundles share a bundle identifier and may share preferences.
if [[ "$OPEN_APP" == 1 ]]; then
  open -n "$APP"
  echo "Preview launch requested. Quit the older QA app manually if both are visible."
fi
