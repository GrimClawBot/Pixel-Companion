# Integrated Alpha — human Mac QA checklist

This file is a **test plan, not proof that testing occurred**. Record exact source SHA, Mac hardware, OS, human result and screenshot/video evidence. Automated unit tests and a launched process do not prove visual/VoiceOver acceptance.

## Environment matrix

- MacBook with notch (compact, hover, 440pt detail), automatic and forced notch.
- No-notch Mac or external-display mode (360pt menu bar), lid open and clamshell.
- External-display hotplug, screen arrangement changes, full-screen Spaces, sleep/wake.
- Dark/light appearance, keyboard-only use, VoiceOver, Reduce Motion and increased text sizes.

## Functional checks

- Launch and Quit, no unexpected Dock icon, Esc/click-outside dismiss, hover flicker and character moods.
- Overview counts, Running/Queued/Failed latest run views, approval ownership clearly company-wide, Attention signals and tap-through to inspector.
- Agents search/filter and List/By role grouping, missing roles visibly unreported, no fabricated departments; long names, session state, real/unknown model/provider, run history cap, reported token and context/budget warnings, Back navigation.
- Activity search/date/type filters, pending approvals/messages, expand Company Tasks and search; only authoritative assigneeAgentId gets inspector routing.
- Optional public GitHub input is blank by default; verify valid owner/repo shows reported workflow/PR statuses, invalid/private/missing repositories fail safely, no credentials are requested, no Paperclip disruption or misleading cached green CI.
- Focus timer OFF by default; opt in through Settings, verify 25/5/15 minute presets, Start/Pause/Resume/Reset, keyboard/VoiceOver in 360pt/440pt modes, persistence across tab/display switches, sleep/wake countdown, no auto-started session, no new OS notifications or files, and clearing on disable/quit.
- Battery & Power widget OFF by default; verify live actual capacity/charging/adapter status, no-battery Mac state, missing/invalid capacity, Mac Low Power Mode and wake refresh, disabling clears readings, and no extra privacy permission or stored battery history. Confirm notch/menu-bar and keyboard/VoiceOver behavior.
- Next Calendar event OFF by default: merely enabling it or launching a QA app must NOT trigger permission. Verify the explicit Grant button with grant/deny/restricted/revoke and optional Show event titles (OFF by default); verify next future event, all-day fallback, recurring/multiple calendars, no local event data persistence or outbound transfer, and narrow-layout VoiceOver.
- Apple Music Now Playing OFF by default: no Automation request on launch, enabling, wake or install; only explicit Connect may ask, and it never opens Music itself. Verify play/pause/stopped, denied/revoked/missing Music, title privacy by default, no history/files, read-only AppleScript source, keyboard and VoiceOver at 360pt/440pt.
- Test no agents, no tasks, missing metrics/timestamps, stale/disconnected Paperclip, recover after reconnect, no old data shown as live.
- All tabs and Command-1..4 shortcuts, scroll reset, 360pt clipping, selected accessibility state, screen reader semantics.
- System notifications opt-in and permission, local QA simulations, no replay or duplicated events, no agent/task details in banners.
- Temporary QA Launch at Login is disabled; final installed release requires separate macOS ServiceManagement registration/unregistration and System Settings verification.
- Remote HTTP to non-loopback rejected, HTTPS accepted, localhost SSH tunnel unchanged; packet inspection confirms GET-only/no host commands.
- Ensure no Mac personal files/settings, Paperclip production state, secrets, source or backups were overwritten during QA replacement.
- Observe CPU, energy, memory, connection polling and responsiveness during idle, run activity, sleep/wake. Verify Paperclip 5-second normal vs 20-second Low Power Mode with default-on toggle, no duplicate polling after wake, mock interval unaffected and the independent GitHub 180-second cadence unchanged.

## Engineering/release gates

Run the strict native gate on final SHA, verify GitHub Actions for that exact SHA, obtain Greptile final-SHA review or explicitly approved substitute and named human/security review for public API and transport changes, then record physical Mac acceptance. User authorization is needed later for official signing/notarization and public binary distribution. All PRs remain unmerged until every applicable gate passes.

Missing v1 capabilities (GitHub/CI, infrastructure, authenticated Atlas chat, privileged approvals, full departments/logs) are **not** covered by this Alpha acceptance plan. Do not treat disabled placeholders as implemented functionality.

- Output volume HUD OFF by default: verify CoreAudio reports only actual default-output master scalar/mute, including nil master controls, USB/HDMI/Bluetooth output and device swaps; turning OFF clears RAM state and stops polling. No volume/mute changes, microphone permission, media recording, device names/IDs, logs or history. Confirm Overview 360pt/440pt VoiceOver on notch and menu bar; wake refresh.

- Display brightness HUD OFF by default: verify current IOKit-reported scalar on a supported single display, 0/100% and malformed/out-of-range/ambiguous/unavailable states, unsupported internal/external devices, lid closed, plugged external monitors and wake. Ensure no private display APIs, Screen Recording/Accessibility permission, brightness mutations, identifiers, telemetry or history. Both notch/menu-bar at 360pt/440pt plus VoiceOver manual acceptance required.

- Downloads HUD is opt-in; with no source it explicitly reports unconnected, with a connected source it shows only valid reported bytes; unknown total never creates percent. Reject negatives, overrun and zero totals; disconnect and disabling stop reads and clear in-memory state. No browser/file activity scanning, filenames, paths, cookies or network permissions. Physical 360/440pt keyboard/VoiceOver review pending provider integration.

- Native Settings redesign PC-036: verify resizable sidebar navigation (General, Connections, Utilities, Notifications), all existing toggles, mock/Paperclip/GitHub draft editing behavior, Launch at Login, permission prompts ONLY after existing explicit buttons, 700×490 up to 1200×900, VoiceOver headings/focus, Keyboard/Tab navigation, Light/Dark Mode, Reduce Motion/Reduce Transparency. Confirm no scroll clipping, changes saved after switching panes, no form height lock.
- Native popover visual refresh: verify updated adaptive cards/selected tab pill with 360×440 menu bar and notch including large Dynamic Type, labels, reduced motion/contrast/light/dark, no overlap, preserved ⌘1–⌘4 and arrow tab navigation, all prior statuses and utilities still readable.

- PC-037 opt-in transient File Shelf: choose explicit files in NSOpenPanel, reject folders and web URLs, 8-file max, duplicated item, show sanitized filename, remove/clear and Finder Reveal. Toggle OFF instantly clears references, relaunch does not restore; no content reads, copies, bookmarks, uploads, backend transfer or logging. Confirm narrow notch/menu-bar, keyboard, VoiceOver, cancel picker, no permission prompt on merely enabling.

- PC-038 Finder file URL drag/drop: accept explicit file references, reject folder URLs with and without directory slash, web URL drags, duplicates and over-limit; no automatic add on startup. Native per-row ShareLink should open the OS share flow only on click, show AirDrop only if macOS offers it, never send without the human choosing a destination. Manual narrow notch/menu-bar drop hit-target and VoiceOver tests pending.

- PC-039 Clipboard: OFF by default and NO background reads. Explicit Save copied text button checks Pasteboard types for concealed/transient/password markers **before** reading plain text. Verify copied unmarked secrets cannot be automatically detected and UI warns users, nil/nontext/large/out-of-bounds/duplicates/secret markers, five-item cap, manual copy/remove/clear, disable/quit purges RAM. No persistence, file/network access, Paperclip dispatch or monitoring timer. Confirm possible macOS paste prompts only after pressing Save, 360/440pt keyboard and VoiceOver QA.

- PC-040 local sessions status: default OFF; no automatic file/agent access even when enabled without explicit NSOpenPanel selection. Test versioned JSON, legitimate Codex/Claude Code/Hermes/custom statuses, up to 12 sessions, stale after 120s, future >30s fail closed, unknown states/providers, duplicate/pathlike IDs, oversized/unreadable file, label bidi/control rejection. Verify files/directories/symlinks rejected, source path forgotten after disable/quit, Settings -> Connections opt-in, independent from Paperclip authority, no fabricated tokens/tasks, wake refresh and no network/CLI execution. Manual VoiceOver and narrow-notch/menu bar visual QA pending; publisher must not be mistaken for a direct agent autodiscovery integration.

- PC-041 opt-in Codex process presence: macOS public sysctl reports current-UID exact "codex" process names only; do not interpret editor app-server idle presence as active session or as verified Codex vendor identity. OFF by default, no syscall while disabled, refresh only enabled (15s), unavailable if process-list read denied, absence not fabricated; redundant enable no duplicate timer, wake updates, disable zeroes reading. Keep separate from Paperclip and PC-040 local-agent source. Test VS Code Codex extension resident/closed and multiple processes, VoiceOver and 360/440 notch/menu bar. Do not read ~/.codex transcripts, credentials, process args or paths.

- PC-042 Codex hook turn-completion: OFF by default and no file reads until explicit folder selection. Strict versioned event-only 2KB schema, future-date rejection, >120s stale display, no claim that turn finished successfully or proves active running. Test no-file-first-run, symlink/special file denial, folder selection and disconnect/disable clears RAM, wake refresh. Python one-shot hook only accepts documented agent-turn-complete and drops input-messages/last-assistant-message/cwd/thread-id/turn-id even when full JSON is received; bounded 256KB input, atomic mode-0600 timestamp-only marker, unsupported events have no side effects, no network/logging/config edits. Manual Codex CLI real notify event and macOS 360/440pt/VoiceOver testing required; VS Code app-server notify support must not be assumed.
