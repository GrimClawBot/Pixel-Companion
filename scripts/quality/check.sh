#!/usr/bin/env bash
# Native quality checks for Pixel-Companion (PC-000 gate).
#
# Usage: scripts/quality/check.sh [--base <ref>]
#   --base <ref>   additionally scan only lines added since <ref> for secrets
#
# Env:
#   QUALITY_XCODE_SCHEME       scheme for xcodebuild (required once an Xcode project exists)
#   QUALITY_XCODE_DESTINATION  default "platform=macOS"
#
# Exit codes: 0 pass, 1 one or more checks failed,
#             2 incomplete (a required toolchain is missing; this is NOT a pass).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

BASE_REF=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_REF="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

declare -a RESULTS=()
FAILED=0
INCOMPLETE=0

record() { RESULTS+=("$(printf '%-10s %-8s %s' "$1" "$2" "${3:-}")"); }

run_stage() {
  local name="$1"; shift
  echo "==> $name: $*"
  if "$@"; then record "$name" PASS; else record "$name" FAIL; FAILED=1; fi
}

missing() { record "$1" MISSING "$2"; INCOMPLETE=1; }
skipped() { record "$1" N/A "$2"; }
have() { command -v "$1" >/dev/null 2>&1; }

SWIFT_SOURCES="$(git ls-files '*.swift' | head -n 1)"
XCODE_CONTAINER="$(git ls-files -- '*.xcworkspace/contents.xcworkspacedata' '*.xcodeproj/project.pbxproj' \
  | grep -v '\.xcodeproj/project\.xcworkspace/' | head -n 1)"
XCODE_CONTAINER="${XCODE_CONTAINER%/*}"

# 1. Tooling self-tests: the gate must be trustworthy before it judges anything.
run_stage tooling python3 -m unittest discover -s scripts/quality/tests -t . -q

# 2. Secrets: every tracked file, plus the added lines of the branch when --base is given.
run_stage secrets python3 scripts/quality/secret_scan.py
if [[ -n "$BASE_REF" ]]; then
  run_stage secrets+ python3 scripts/quality/secret_scan.py --range "$BASE_REF...HEAD"
fi
if have gitleaks; then
  run_stage gitleaks gitleaks detect --no-banner --redact --source .
else
  skipped gitleaks "optional; built-in scanner ran"
fi

# 3. Dependency/config validation.
run_stage config python3 scripts/quality/validate_config.py

# 4. Lint/static checks.
if [[ -z "$SWIFT_SOURCES" ]]; then
  skipped lint "no Swift sources yet"
elif ! have swiftlint; then
  missing lint "swiftlint not installed (brew install swiftlint)"
else
  run_stage lint swiftlint lint --strict --quiet
fi

# 5/6. Clean build with diagnostics as errors, then unit tests.
if [[ -f Package.swift ]]; then
  if have swift; then
    run_stage resolve swift package resolve --force-resolved-versions
    run_stage build swift build -Xswiftc -warnings-as-errors
    run_stage test swift test -Xswiftc -warnings-as-errors
  else
    missing build "swift toolchain not installed"
    missing test "swift toolchain not installed"
  fi
fi
if [[ -n "$XCODE_CONTAINER" ]]; then
  if ! have xcodebuild; then
    missing xcode "xcodebuild unavailable (requires macOS + Xcode)"
  elif [[ -z "${QUALITY_XCODE_SCHEME:-}" ]]; then
    missing xcode "set QUALITY_XCODE_SCHEME"
  else
    flag=-project; [[ "$XCODE_CONTAINER" == *.xcworkspace ]] && flag=-workspace
    xc=(xcodebuild "$flag" "$XCODE_CONTAINER" -scheme "$QUALITY_XCODE_SCHEME"
        -destination "${QUALITY_XCODE_DESTINATION:-platform=macOS}"
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES CODE_SIGNING_ALLOWED=NO)
    run_stage xcode-build "${xc[@]}" clean build
    run_stage xcode-test "${xc[@]}" test
  fi
fi
if [[ ! -f Package.swift && -z "$XCODE_CONTAINER" ]]; then
  if [[ -n "$SWIFT_SOURCES" ]]; then
    record build FAIL "Swift sources without Package.swift or Xcode project"; FAILED=1
  else
    skipped build "no Swift package or Xcode project yet"
    skipped test "no Swift package or Xcode project yet"
  fi
fi

echo
echo "Quality gate summary ($(git rev-parse --short HEAD))"
printf '%s\n' "${RESULTS[@]}"
if [[ $FAILED -ne 0 ]]; then echo "RESULT: FAIL"; exit 1; fi
if [[ $INCOMPLETE -ne 0 ]]; then echo "RESULT: INCOMPLETE (not a pass; run on macOS with the toolchain)"; exit 2; fi
echo "RESULT: PASS"
