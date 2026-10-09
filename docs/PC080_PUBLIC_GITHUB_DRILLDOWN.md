# PC-080 — Public GitHub evidence links (read-only)

## Purpose and data boundary

Pixel Companion already offers an **optional**, unauthenticated public
GitHub activity source. Until now, its overview showed the three most
recent CI runs and open PRs but had no user-facing route to inspect
their primary evidence.

PC-080 adds **user-triggered browser links** to the source GitHub pages,
plus source-reported workflow branch names. This is a useful public
PR/CI drilldown without a private GitHub integration.

## Behavior

- The configured repository is still provided by the local user's existing
  **owner/repo** setting. The validation rejects arbitrary URLs,
  credentials, slashes, whitespace and unsafe components.
- Each public workflow run links to
  `https://github.com/<owner>/<repo>/actions/runs/<positive-run-id>`.
  A reported branch is shown as text only, never interpolated into the
  destination URL. Missing branch stays omitted.
- Each public PR links to
  `https://github.com/<owner>/<repo>/pull/<positive-pr-number>`.
  There is also an explicit **View public repository** link.
- URLs are constructed exclusively from the validated repository and
  positive numeric IDs. **API-provided html_url is ignored**, preventing
  an API response from redirecting an in-app control to an unrelated
  host. Invalid or absent IDs show noninteractive rows.
- Linking requires an explicit click/tap via a native SwiftUI `Link`;
  Pixel Companion does not open a browser automatically.
- The existing freshness contract remains: loading, unavailable,
  rate-limited or disabled source states never show stale green CI or
  previously cached actionable links. At most three current runs/PRs
  appear. No PR review, merge, comment, commit or status mutation.
- No additional network requests, OAuth login, private repository
  access, token storage, or hardcoded Pixel organization details.
  A browser opened by user choice may have its own separate login.

## Native regression and Mac acceptance

New macOS XCTest checks: validated GitHub HTTPS host/path, positive
run/PR IDs, zero/negative link refusal, hostile owner/repo rejection,
public source branch presentation without navigation influence, and
ignoring untrusted `html_url` in response JSON. Existing
`PublicGitHubMonitorTests` verify the monitor makes exactly two
GET requests to the public API with no Authorization header.

On the owner Mac:

1. In Settings → Connections, optionally configure a known **public**
   repository; do not enter private credentials or a private repository.
2. Open the public GitHub CI panel. Verify workflow name/status,
   source-reported branch if present, and explicit external link glyph.
3. Click a run/PR and confirm **github.com** with the exact selected
   repository and numeric ID; no action is sent to Paperclip.
4. Change the configured repo or disable the source: old rows and
   links must disappear rather than remaining active.
5. Test GitHub unavailable/rate-limited and poor connectivity; the
   UI must report unavailability, not claim live green CI.
6. Test 360pt/440pt widths, long PR titles/branch names,
   VoiceOver, keyboard navigation and external-display fallback.

## QA80 installation (owner-local)

Quit QA78 via its in-app Quit control; preserve it for rollback.
Use a fresh source checkout for the new QA build:

```bash
mkdir -p "$HOME/Developer" &&
git clone --depth 1 --branch pc-080/public-github-evidence-links \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA80" &&
bash "$HOME/Developer/Pixel-Companion-QA80/scripts/qa_preview_macos.sh" --qa-number 80
```

The hardened installer refuses any pre-existing QA80 path (including
symlinks), uses an isolated temporary QA Info.plist, checks the signature
and exact `PCQAUpdateNumber=80` before opening, and leaves older apps
untouched. QA login-item changes remain unavailable by design.

To revert, quit QA80 and reopen the verified older QA78 path:

```bash
open -n "$HOME/Applications/Pixel Companion QA Update 78.app"
```

Older QA bundles can be retired only **after** the new app is verified
and checked; this code does not automatically delete or replace them.
QA bundles share one app identity and may share local preferences; do
not run multiple copies at the same time.

## Approval gates

This is a draft stacked PR. Exact-head native macOS CI, Greptile
technical review, independent human GitHub approval, and Mac UI/VoiceOver
acceptance remain distinct. Do not merge protected main, publish a
binary release, request a new entitlement or enable GitHub write scopes.
