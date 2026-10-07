#!/usr/bin/env bash
# Local app packaging only: no publishing, notarization, or remote calls.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CALLER="$(pwd -P)"
MODE=release
DEFAULT="$ROOT/dist/Pixel Companion.app"
OUTPUT="$DEFAULT"
IDENTITY="-"

usage() {
  echo "Usage: $0 [--debug|--release] [--output /path/App.app] [--sign-identity 'Developer ID Application: ...']"
}
while (( $# )); do
  case "$1" in
    --debug) MODE=debug; shift ;;
    --release) MODE=release; shift ;;
    --output) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; OUTPUT="$2"; shift 2 ;;
    --sign-identity) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; IDENTITY="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ "$OUTPUT" == *.app ]] || { echo "Output must end in .app" >&2; exit 2; }
[[ "$OUTPUT" == /* ]] || OUTPUT="$CALLER/$OUTPUT"
OUTPUT="$(python3 -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$OUTPUT")"
if [[ -e "$OUTPUT" && "$OUTPUT" != "$DEFAULT" ]]; then
  echo "Refusing to replace existing app at $OUTPUT" >&2
  exit 2
fi
if [[ "$IDENTITY" != "-" && "$MODE" != "release" ]]; then
  echo "Developer ID signing requires release mode" >&2
  exit 2
fi
for tool in swift codesign sips iconutil python3 plutil; do command -v "$tool" >/dev/null; done
plutil -lint "$ROOT/packaging/Info.plist"
cd "$ROOT"
swift build -c "$MODE" --product PixelCompanion -Xswiftc -warnings-as-errors
EXECUTABLE="$(swift build -c "$MODE" --show-bin-path)/PixelCompanion"
[[ -x "$EXECUTABLE" ]] || { echo "Executable missing" >&2; exit 1; }

TMP="$(mktemp -d /tmp/pixel-companion-package.XXXXXXXX)"
STAGE=""
cleanup() {
  rm -rf "$TMP"
  if [[ -n "$STAGE" ]]; then
    if [[ -e "$STAGE/Previous.app" && ! -e "$OUTPUT" ]]; then
      echo "RECOVERY REQUIRED: previous app preserved at $STAGE/Previous.app" >&2
    else
      rm -rf "$STAGE"
    fi
  fi
}
trap cleanup EXIT
APP="$TMP/Pixel Companion.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP/PixelCompanion.iconset"
cp "$EXECUTABLE" "$APP/Contents/MacOS/PixelCompanion"
cp packaging/Info.plist "$APP/Contents/Info.plist"
python3 scripts/quality/make_icon.py "$TMP/source-icon.png"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$TMP/source-icon.png" \
    --out "$TMP/PixelCompanion.iconset/icon_$size""x$size.png" >/dev/null
  double=$((size * 2))
  sips -s format png -z "$double" "$double" "$TMP/source-icon.png" \
    --out "$TMP/PixelCompanion.iconset/icon_$size""x$size@2x.png" >/dev/null
done
iconutil -c icns "$TMP/PixelCompanion.iconset" \
  -o "$APP/Contents/Resources/PixelCompanion.icns"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  # Offline Developer ID signing; public notarization must be separately approved.
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

# Stage on the destination filesystem before touching an existing bundle.
mkdir -p "$(dirname "$OUTPUT")"
STAGE="$(mktemp -d "$(dirname "$OUTPUT")/.pixel-companion-stage.XXXXXXXX")"
cp -R "$APP" "$STAGE/New.app"
codesign --verify --strict "$STAGE/New.app"
python3 scripts/quality/install_bundle.py "$STAGE/New.app" "$OUTPUT" "$DEFAULT"
echo "BUNDLE: $OUTPUT"
echo "SIGNING: $([[ "$IDENTITY" == "-" ]] && echo local-ad-hoc || echo developer-id)"
echo "NOTE: No notarization or publishing occurred."
