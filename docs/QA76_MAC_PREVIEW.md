# PC-076 — Compact notch refinement and QA76 Mac preview

## Visible changes from QA74

PC-076 incorporates the owner's QA74 notch feedback without changing the
physical camera housing footprint or any other accepted component.

- The animated pixel character and its reported status form **one centered,
  vertically aligned pair** for normal states such as Idle, Working,
  Thinking and Coding. Compact notch stays at the QA74 32pt extension and
  retains the same 2.6pt pixel blocks.
- Normal statuses no longer repeat their meaning in a trailing SF Symbol
  (e.g. the Working hammer is hidden in the compact strip only).
- The label uses a slightly larger **12pt rounded semibold** font with stronger
  contrast and single-line scaling in the same bounded notch width.
- Important source-backed states still keep their indicator: actual pending
  approval count, errors, offline, security/infrastructure/budget alerts,
  and verified success. Stale/connecting/unavailable Paperclip data still
  switches the character to grey and displays a source warning.
- Expanded hover and detail panels retain their previous placement and
  complete icon/status behavior. The menu-bar fallback is unchanged.
- The original pixel sprite and all 4 tabs, Settings, Paperclip,
  agent/task/run navigation, context intelligence and QA Login Items guards
  remain intact. No network writes or additional permissions.

## Owner-local QA76 installation

Quit the active QA74 using its own Quit control, but **do not delete it**.
From Terminal on the Mac:

```bash
mkdir -p "$HOME/Developer" &&
git clone --depth 1 --branch pc-076/compact-status-refinement-qa76 \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA76" &&
bash "$HOME/Developer/Pixel-Companion-QA76/scripts/qa_preview_macos.sh" --qa-number 76
```

This clone is separate from QA72 and QA74 worktrees, and the build creates
only `~/Applications/Pixel Companion QA Update 76.app` if that app path does
not exist. Existing apps, symlinks, source worktrees and preferences are
never deleted/replaced by the installer.

The same hardened installer accepts **only 72, 74, or 76**. Run with
`--print-plan --qa-number 76` to inspect the planned path and QA marker
without touching the filesystem or building an app; use `--no-open`
to build/verify without automatically launching. Git-source cleanliness,
private per-build Info.plist, offline ad-hoc signing, signed QA marker
verification, safe custom-output replacement refusal and disabled QA
Launch at Login remain enforced. It never publishes a binary.

Both QA74 and QA76 use the same bundle identifier and may share local
preferences/connection settings. **Do not run both simultaneously.**

## Manual Mac visual and accessibility acceptance

1. Settings → General: `0.1.0 (build 76)` and `QA Update #76`, with
   Launch at Login unavailable because the app is a disposable QA build.
2. In the *collapsed notch* with Paperclip connected and Working: original
   character + Working label are visibly centered vertically and
   horizontally as a unit; **no redundant hammer** at the far right.
   Compare at identical screen resolution with QA74 screenshot.
3. Change to Idle, Coding, a real pending approval, a security/budget/error
   alert, a delayed refresh, disconnected and connecting. The indicator
   should only appear when it carries additional meaning. Approval
   counts are shown only on a live source. Stale must never appear active.
4. Hover/click/escape/outside-dismiss. Expanded snapshot/details must
   retain all original features and status symbols.
5. Check surrounding system menu icons at native scale, zoomed display
   scaling, long status names, narrow notch, VoiceOver and Reduce Motion.
   Never cover macOS menu bar neighbors.
6. Exercise the no-notch external-display/menu-bar fallback and verify
   all Settings, 4 tabs, task→run, Reporting and context views still exist.

## Roll back without deleting anything

Quit QA76 in its UI, then reopen QA74:

```bash
open -n "$HOME/Applications/Pixel Companion QA Update 74.app"
```

If the previous QA app was installed elsewhere, open its verified path.
Do not delete QA74 or QA72; no automatic cleanup of your existing
applications or preferences occurs.

## Review boundaries

This is owner-local preview documentation, not confirmation that QA76
has been installed. Native CI tests source but does not replace owner
device screenshot/VoiceOver acceptance. Greptile, independent GitHub
human approval and owner-controlled integration are separate gates.
Do not merge protected `main`, publish public binaries, mutate
Paperclip, or enable macOS Login Items as part of a QA preview.
