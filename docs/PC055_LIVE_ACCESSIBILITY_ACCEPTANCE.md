# PC-055 — Live macOS accessibility acceptance

Date: October 8, 2026. Installed app: local QA53, commit b6fddf270e9a72baa93b6f19f9106bd4af1ccf36.

## Running-window evidence

On the authorized MacBook, System Events reports accessibility enabled. The real Pixel Companion menu-bar item opened its live popover, showing Overview, Agents, Usage, Activity, Paperclip Connected, the read-only indicator and Settings.

An initial AppleScript inspection returned empty button name fields. Native AXUIElement inspection confirmed each tab actually has its proper AXDescription, AXAttributedDescription and AXIdentifier:

| Identifier | Semantic description |
| --- | --- |
| companion.tab.overview | Overview tab |
| companion.tab.agents | Agents tab |
| companion.tab.usage | Usage tab |
| companion.tab.activity | Activity tab |

Each tab has AXValue Selected/Not selected. Native AXPress on all four real buttons returned AXError success (0), and each subsequently reported Selected. The empty AppleScript name field was an inspection limitation, NOT an actual missing accessibility label. No redundant product patch was appropriate.

## Reproduce locally

Open the Pixel Companion menu-bar popover and run:

    swift scripts/quality/verify_live_accessibility.swift <running_PID> --exercise-tabs

Without --exercise-tabs the script is read-only. With the flag it only activates the four existing navigation tabs. It requires user-approved Accessibility for the invoking host, refuses inaccessible or hidden UI, and prints only test status. It does not capture a screenshot or read prompts, credentials, provider content, messages or private files.

## Review status and outstanding gates

CodeRabbit is installed but skipped draft PR #121 by default. A deliberate @coderabbitai review comment was posted and the bot acknowledged the review request. At this report time there was no final independent code review verdict. A bot request is not formal review approval.

Actual spoken VoiceOver output, Tab/Shift-Tab keyboard navigation and arrow focus, reduced motion, macOS Focus/notifications, non-notch/multi-display hardware, and independent security review remain OPEN. Native accessibility API presses alone do not establish all these requirements.

This is documentation and QA tooling only. QA53 stays installed and running. No provider configuration, Paperclip production, main branch, or public release is changed.
