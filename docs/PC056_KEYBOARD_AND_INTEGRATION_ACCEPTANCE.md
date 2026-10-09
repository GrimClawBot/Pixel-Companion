# PC-056 — Live keyboard navigation and integration checkpoint

## Live Mac acceptance (October 8, 2026)

The authorized MacBook, running QA54, opened the actual Pixel Companion
menu-bar popover and sent Command+1, +2, +3, +4 via System Events.
After every keystroke the matching tab reported Selected and the other
three were Not selected: four of four checks passed. Prior PC-055 checks
confirmed all four native accessibility labels and direct AXPress.

To reproduce with the actual popover OPEN and Accessibility enabled:

    osascript scripts/quality/verify_live_keyboard.applescript <app_pid>

The script refuses missing Accessibility, wrong process PID, a closed
popover, missing AXValue, multiple selected tabs or a wrongly selected tab.
It changes only the selected UI tab. It reads no provider requests, prompts,
credentials or personal files and captures no screenshots.

Spoken VoiceOver audio, full keyboard-only focus order and navigation,
screen-reader rotor, reduced-motion hardware, macOS Focus/notifications
and non-notch/multi-display tests remain UNVERIFIED. Keyboard shortcuts
do not prove those other acceptance goals.

## Review and integration status

QA54 runs at source f9dcff1dd8b369d5d3476e9d859f5400dda76de9.
CodeRabbit's actionable Paperclip path-ID concern was fixed in PC-054 and
included in PC-055. The bot's COMMENTED review is not approval; no
independent formal GitHub APPROVED decisions were recorded on the latest
PRs when last checked. User-reviewed visual confirmation permits moving
forward with quality review but must not impersonate independent security
approval or VoiceOver speech acceptance.

The cumulative candidate has a clean virtual merge into main. It still
requires reviewed dependency cuts and release evidence before main merge
or public distribution. This PC-056 change contains QA tooling and docs
only: do NOT replace the running QA54 app merely to install unchanged UI
code. No changes to Paperclip, Codex, Claude or Sky notifier configurations.
