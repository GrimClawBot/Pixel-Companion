# QA72 — Owner-local Mac preview (not a public release)

## What's in this preview

Build this source branch on the owner's own Mac to see the accumulated
Pixel Companion work through PC-072: notch/menu-bar, four tabs, Apple-like
Settings, optional private read-only Paperclip connectivity, context
next-step guidance, task→linked-run drilldown and the new read-only
Reporting hierarchy with local expand/collapse controls.

**This is not the same as QA61.** QA61 remains an untouched rollback.
PC-065 Launch at Login is intentionally **disabled for QA72** by writing
`PCQAUpdateNumber=72` to the app's Info.plist *before* ad-hoc signing.
Do not test real macOS Login Items on a temporary QA app.

## Local install steps

1. In the running QA61, use its **Quit** control to avoid two menu-bar/notch
   companions appearing at once. Do not delete QA61, its preferences, or
   its already installed bundle.
2. Open macOS Terminal and run the following **from a trusted repository**
   (these commands clone source, build/sign locally, verify, and open QA72):

```bash
git clone --depth 1 --branch pc-073/local-qa72-preview \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA72" &&
bash "$HOME/Developer/Pixel-Companion-QA72/scripts/qa_preview_macos.sh"
```

If `~/Developer/Pixel-Companion-QA72` already exists, this deliberately
refuses to clone over it. Use a separate empty directory; never blindly
delete existing project files.

- Builds only with the local macOS Swift toolchain. It refuses non-Mac,
  modified, untracked, or ignored build inputs and any pre-existing QA72
  destination (including a symlink). It uses the existing
  `scripts/package_macos.sh` safeguards.
- Copies the checked-in Info.plist to a private temporary file, adds QA
  metadata only to that copy, and passes it explicitly to the packager.
  The tracked source plist is never changed or shared with other builds;
  the temporary copy is cleaned on exit. Packaging verifies its signature,
  confirms the embedded QA marker and prints the exact source commit SHA.
- Creates a **new** app at
  `~/Applications/Pixel Companion QA Update 72.app`; does NOT overwrite
  the existing QA61 app, canonical `dist/Pixel Companion.app`, or any
  other installed app. No auto-updater, credential upload, login
  registration, Finder destructive operation or GitHub release.
- If you prefer to inspect the app before opening it, pass `--no-open` and
  later use `open -n "$HOME/Applications/Pixel Companion QA Update 72.app"`.

## Manual acceptance checklist

- Mac displays QA Update #72 in Settings. If it does not, stop using the
  build. Launch at Login is shown as unavailable in the QA build.
- Agents tab List / By role / Reporting. In mock mode, absence of real
  Paperclip reporting IDs must *not* invent a hierarchy.
- On an explicitly connected live Paperclip instance, check real manager
  reporting IDs, expand/collapse all, current-assignee links, task→run
  provenance, stale/unknown states, and no runtime mutation.
- Usage tab: context guidance is reported-only; Keep working for now is
  local and does not create or submit a chat.
- UI: both the notch and the menu-bar fallback, all four tabs, 360pt/440pt
  widths, long agent names, keyboard navigation, settings, Reduce Motion,
  and VoiceOver.
- No new permissions, Login Items changes, secret in notifications, or
  commands to Paperclip. Do not connect a real private server unless you
  choose to enter its URL yourself.

## Rollback

Quit QA72 using its UI. Reopen the untouched known-good QA61:

```bash
open -n "$HOME/Developer/Pixel-Companion/dist/Pixel Companion QA Update 61.app"
```

If QA61 is installed elsewhere, use the location you previously verified.
No automatic cleanup of QA61 or Mac user preferences is allowed. Never
copy private connection values into GitHub.

## Review and security gates

The QA72 local preview is **not** a signed, notarized or approved public
release and must not be uploaded as a public GitHub binary or artifact.
Green CI validates source tests, not UI/VoiceOver/actual machine behavior.
The selected snapshot includes PRs #144, #146-#147 and #149-#154 on a
stacked *draft* branch; none of this grants protected-main merge approval.
Greptile corrected-head review, independent human GitHub review, Mac
acceptance of Launch at Login (#148), and owner-authorized integration
remain independent gates.
