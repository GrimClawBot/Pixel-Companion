# PC-079 — Owner-approved QA78 update and safe retirement of older QA apps

The owner authorized updating Pixel Companion on their Mac and deleting
old temporary QA builds. **Remote Desktop Commander still reports an
exhausted account-level monthly call quota**, so these steps have to be
run by the owner locally until that access becomes available. No automated
remote Mac update or deletion is claimed.

## Step 1 — Update the Mac to QA78

Quit the currently running QA77 using its **Quit** control. Do not remove
anything yet. Run in Terminal:

```bash
mkdir -p "$HOME/Developer" &&
git clone --depth 1 --branch pc-079/owner-verified-qa78-retirement \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA78-Checked" &&
bash "$HOME/Developer/Pixel-Companion-QA78-Checked/scripts/qa_preview_macos.sh" --qa-number 78
```

This creates **only** the new
`~/Applications/Pixel Companion QA Update 78.app`. It refuses
to overwrite any existing QA78 app or symlink. The installer checks that
the source tree is clean, uses a private QA Info.plist for signing,
verifies code signature and the `PCQAUpdateNumber=78` marker, and leaves
macOS Launch at Login disabled for temporary QA.

If the separate QA78 bundle already exists, **don't overwrite it**.
You can open and inspect it using its Finder app icon.

## Step 2 — Accept the new build

In Settings → General confirm:
- **0.1.0 (build 78)**
- **QA Update #78**
- Launch at Login unavailable in temporary QA

Verify Agents → select an agent → **Handoff readiness · review only**
and that Overview, Activity, Usage, the notch/hover menu and all existing
utilities remain functional. This feature is read-only and must not
submit anything to Paperclip. Do not delete any prior version until you've
confirmed the new app opens and the key screens work.

## Step 3 — Show exactly which old apps would be moved

After verifying QA78, in Terminal:

```bash
bash "$HOME/Developer/Pixel-Companion-QA78-Checked/scripts/retire_old_qa_macos.sh" --dry-run
```

This checks the exact installed QA78 marker, Info.plist identity,
and signed app before listing candidates.

The only eligible old app paths are:
- `~/Applications/Pixel Companion QA Update 61.app`
- `~/Applications/Pixel Companion QA Update 72.app`
- `~/Applications/Pixel Companion QA Update 74.app`
- `~/Applications/Pixel Companion QA Update 76.app`
- `~/Applications/Pixel Companion QA Update 77.app`

Older QA copies elsewhere, Developer source repositories, other apps,
custom builds, user documents, Paperclip configuration, Keychain contents,
preferences and login items are **not** eligible. The script skips apps
whose signatures, markers, bundle identifiers, expected executable or
paths don't match. Symlinks and app bundles appearing to be in use
are skipped. If QA78 is missing, invalid or unexpectedly signed,
**nothing is moved**.

## Step 4 — Retire verified old apps to the macOS Trash

Only after the new QA78 is working and the preview list looks right,
run the following command:

```bash
bash "$HOME/Developer/Pixel-Companion-QA78-Checked/scripts/retire_old_qa_macos.sh" --apply
```

Eligible old app bundles are **moved, not permanently erased**,
to a newly created private folder under the owner's `~/.Trash`.
The script prints each destination and the recovery folder path.
Nothing is killed, no configuration or source file is deleted, and
QA78 stays installed. macOS Trash can be restored if a rollback is
needed; **do not empty the Trash** until you're satisfied.

If a previous QA app lives outside `~/Applications`, leave it in place
for separate inspection. Do not run manual wildcard or recursive deletion
commands against `~/Developer`, `~/Applications` or user data.

## Quality and review gates

- The older PC-078 feature remains on draft PR #160 with fixed Greptile
  findings for agent switching and visible source IDs.
- PC-079 is a separate stacked draft PR; native Mac CI must pass tests
  for a bad QA78 marker, no-op dry run, signed old app migration,
  wrong app identity and symlink refusal.
- A real user launch check and a human review remain necessary.
  Green CI isn't confirmation that the Mac has been updated.
- No protected-main merge, production backend mutation, actual macOS
  Login Items registration, notarization or public release is authorized
  by this temporary QA workflow.
