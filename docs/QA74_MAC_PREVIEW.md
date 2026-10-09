# QA74 — Compact Notch Mac Preview (owner-local, not a release)

## Scope

QA74 is a separate disposable Mac bundle for evaluating the PC-074 compact
notch UI built atop the completed PC-070–PC-073 source stack. It retains
all existing native features, including Agents → Reporting, task-to-run
drilldown, context guidance, four tabs, Settings, and read-only Paperclip.

The visual difference from QA72 is intentionally limited:

- Compact status strip beneath the camera housing is 32pt instead of 24pt.
- Original animated pixel character is larger: 2.6pt blocks instead of 2pt.
- A short text label identifies the reported working/idle/alert mood.
- On stale, connecting, or unavailable Paperclip feeds, the character
  switches to its grey/offline appearance and the label explicitly says
  Updates delayed, Connecting, or Disconnected.
- Expanded hover/detail and no-notch menu-bar fallback stay unchanged.

These are planned behaviors tested in source CI, not a claim of completed
real-device visual or VoiceOver acceptance.

## Install side-by-side with QA72 and QA61

1. **Quit the running QA72 through its own app's Quit button.** Do not
   delete its app bundle or settings. Running two versions simultaneously
   is not recommended: both have the same app bundle identifier.
2. In Terminal, paste the following commands. They clone a fresh, independent
   QA74 source tree and compile/sign on *your own Mac*:

```bash
mkdir -p "$HOME/Developer" &&
git clone --depth 1 --branch pc-075/local-qa74-preview \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA74" &&
bash "$HOME/Developer/Pixel-Companion-QA74/scripts/qa_preview_macos.sh" --qa-number 74
```

Before building, you may run `bash scripts/qa_preview_macos.sh --qa-number 74 --print-plan` inside the clean preview clone to show the planned QA number, app path and marker **without** touching files or installing anything.

If `~/Developer/Pixel-Companion-QA74` already exists, Git safely refuses
to clone over it. Do not blindly remove or overwrite working directories.
Building requires macOS 14+, Xcode/Swift toolchain, the standard macOS
bundling utilities and internet access **only to clone source**. No
credentials are needed for the build; the packaging script itself makes
no publishing or notarization request.

The script creates only:

```
~/Applications/Pixel Companion QA Update 74.app
```

It **refuses to replace** an existing QA74 path, including symlinks, and does
not touch `Pixel Companion QA Update 72.app`, QA61, or the canonical
release app. You can use `--no-open` after `--qa-number 74` to install
without launching. It verifies the ad-hoc code signature and checks the
exact `PCQAUpdateNumber=74` marker inside the signed bundle.

The QA marker keeps **Launch at Login disabled** for this temporary preview.
The installer does not call macOS Login Items APIs, quit existing processes,
change user preferences, talk to Paperclip, create a GitHub Release, or
publish a binary. The app will use your local settings once opened; **QA72
and QA74 may share preferences** because they use the same app bundle ID.
Don't treat the two builds as isolated accounts or separate data profiles.

## Acceptance after launching

- In Settings → General, confirm Version `0.1.0 (build 74)` and
  `QA Update #74`. If these labels do not match, stop and report the
  build output rather than proceeding.
- Capture a compact-notch screenshot showing the larger character and
  readable status. Compare with your QA72 screenshot at the same macOS
  resolution and display scaling.
- Hover/click/dismiss: expand/collapse still works without covering other
  Mac menu-bar controls. Verify both normal and Reduce Motion settings.
- Test actual Paperclip feed freshness, then manually choose no-connect
  or disconnected mode. Stale status must not look like a live working run.
- In Agents, verify List / By role / Reporting are retained and the
  manager expand/collapse controls still work for genuinely reported IDs.
- Verify all original utilities, Usage and Activity remain available and
  the macOS Login Item toggle stays disabled for this QA build.
- Test VoiceOver for one status announcement rather than two, keyboard
  handling, MacBook notch vs menu-bar fallback, and a long alert label.

## Rollback — no uninstall required

Quit QA74 through its UI. Reopen QA72:

```bash
open -n "$HOME/Applications/Pixel Companion QA Update 72.app"
```

If your QA72 was installed at a different path, open that verified path
instead. Do **not** delete QA74 or QA72 automatically. Restore or change
your local settings only through the app.

## Change control

Source development/QA remains on draft stacked PRs. Automated native
tests do not approve external distribution, protected `main` integration,
backend writes, or real macOS Login Items testing. Greptile technical
review, independent human GitHub approval, and owner-observed real Mac
layout/VoiceOver acceptance are separate gates. Remote Mac installation
was not performed because the connected Desktop Commander account's
monthly remote calls remain exhausted.
