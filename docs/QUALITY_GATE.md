# Engineering quality gate (PC-000)

No feature work (PC-001 onward) is accepted until it has passed every stage below,
in order. A stage that cannot run is **not** a pass.

```
Builder (Claude/Codex)
  → native checks        scripts/quality/check.sh
  → Greptile review      scripts/quality/greptile_review.py
  → fix loop             fix → native checks → Greptile, until clean
  → QA acceptance        real macOS runtime/UI verification
  → merge
```

## 1. Native checks

```sh
scripts/quality/check.sh --base origin/main     # or: make quality
```

Run on macOS with Xcode and SwiftLint installed. CI runs the same script on
`macos-15` (`.github/workflows/quality.yml`).

| Stage      | What it proves                                                                  |
|------------|---------------------------------------------------------------------------------|
| tooling    | the gate's own scripts pass their unit tests (`make quality-tests`)            |
| secrets    | no secret patterns or forbidden files (`.env`, `*.p12`, provisioning profiles, private keys) in tracked files; `secrets+` scans every commit introduced by the branch so add-then-delete secrets still fail; gitleaks also runs when installed |
| config     | every tracked JSON / plist / entitlements file parses; root SwiftPM and Xcode-managed remote package dependencies have a committed `Package.resolved` |
| lint       | `swiftlint lint --strict`                                                       |
| resolve    | `swift package resolve --force-resolved-versions` (lockfile is authoritative)  |
| build/test | `swift build` / `swift test` with `-warnings-as-errors`                         |
| xcode-*    | `xcodebuild clean build` and `test` with Swift/Clang warnings as errors; set `QUALITY_XCODE_SCHEME` |

Exit codes: `0` pass, `1` fail, `2` incomplete (toolchain missing). Stages
marked `N/A` only apply while the repository has no Swift package or Xcode
project; as soon as Swift sources exist, a missing toolchain makes the run
incomplete.

A secret finding is reported as `path:line: rule` and never echoes the value.
If a match is a genuine false positive, add `quality:allow-secret` on that
line and justify it in the PR; reviewers treat every use as a review item.

## 2. Greptile review

Prerequisites (one-time, operator): enable `GrimClawBot/Pixel-Companion` in the
Greptile dashboard (GitHub app installed with repository access) so PRs get
automatic reviews driven by `greptile.json`, and issue a Greptile API key for the
CLI.

Agent-friendly CLI review of **committed** changes:

```sh
export GREPTILE_API_KEY=…   # from the secret store, never committed
export GITHUB_TOKEN=…       # read access to the repo
scripts/quality/greptile_review.py --base origin/main --out quality-reports/greptile-$(git rev-parse --short HEAD).json
# or: make review
```

It refuses a dirty working tree, sends `base...HEAD` to Greptile with the
indexed repository as context, and writes a JSON report (`verdict`, `findings`,
`sensitive_reasons`, `head_sha`).

| Exit | Verdict                 | Meaning                                                             |
|------|-------------------------|---------------------------------------------------------------------|
| 0    | `pass`                  | no blocker/major findings and no sensitive surface                  |
| 1    | `blocked`               | at least one **release-blocking** (blocker or major) finding        |
| 2    | `incomplete`            | missing credentials, dirty tree, diff > 120 KB, API or parse error  |
| 3    | `human_review_required` | clean review, but the change touches a sensitive surface            |

Rules:

- Unknown severities are escalated to `blocker`; an unparseable response is
  `incomplete`, never clean.
- **Never auto-approve** changes touching auth, secrets/keychain, CI
  (`.github/`, `Makefile`, `scripts/quality/`, `greptile.json`), dependencies,
  build config, entitlements/`Info.plist`/ATS, or Swift `public`/`open` API.
  These need a named human/security reviewer even when Greptile is clean.
- Oversized diffs are rejected: split the PR.

## 3. Fix loop

On `blocked`: the builder fixes every blocker/major finding **in new commits**
(no force-push squashing during review), reruns `check.sh`, then reruns
`greptile_review.py`. Repeat until the verdict is `pass` (or
`human_review_required` with the reviewer assigned). Attach every report to
the PR so the review → fix → rerun history is auditable. Minor/nit findings are
fixed or explicitly answered in the PR.

## 4. QA acceptance

Only after Greptile is clean, the builder hands QA a test plan covering:
the build SHA under test, macOS version/hardware (notch vs. non-notch),
launch/quit, the changed UI states with screenshots or recordings, permission
prompts, multi-display and sleep/wake behaviour where relevant, and any
regression areas called out by Greptile. QA verifies on a real Mac and records
evidence on the issue. QA failure sends the change back to step 1.

## Definition of done for a feature issue

- Native checks `RESULT: PASS` on the final SHA (CI green).
- Greptile report for the final SHA with verdict `pass`, or
  `human_review_required` plus the human approval.
- QA acceptance evidence on the issue.
