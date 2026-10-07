#!/usr/bin/env bash
# Local app packaging only: no publication, notarization, or remote calls.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=release
OUTPUT="$ROOT/dist/Pixel Companion.app"
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
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/Pixel Companion.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP/PixelCompanion.iconset"
cp "$EXECUTABLE" "$APP/Contents/MacOS/PixelCompanion"
cp packaging/Info.plist "$APP/Contents/Info.plist"
python3 scripts/quality/make_icon.py "$TMP/source-icon.png"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$TMP/source-icon.png"     --out "$TMP/PixelCompanion.iconset/icon_$size""x$size.png" >/dev/null
  double=$((size * 2))
  sips -s format png -z "$double" "$double" "$TMP/source-icon.png"     --out "$TMP/PixelCompanion.iconset/icon_$size""x$size@2x.png" >/dev/null
done
iconutil -c icns "$TMP/PixelCompanion.iconset"   -o "$APP/Contents/Resources/PixelCompanion.icns"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
mkdir -p "$(dirname "$OUTPUT")"
# Never destroy a caller-selected app bundle; only replace our default local build.
if [[ -e "$OUTPUT" ]]; then
  if [[ "$OUTPUT" == "$ROOT/dist/Pixel Companion.app" ]]; then
    rm -rf "$OUTPUT"
  else
    echo "Refusing to replace existing app at $OUTPUT" >&2
    exit 2
  fi
fi
mv "$APP" "$OUTPUT"
echo "BUNDLE: $OUTPUT"
echo "SIGNING: $([[ "$IDENTITY" == "-" ]] && echo local-ad-hoc || echo developer-id)"
echo "NOTE: No notarization or publishing occurred."
