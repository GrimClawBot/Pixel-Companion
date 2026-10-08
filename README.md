# Pixel Companion

Pixel Companion is an independent native macOS 14+ notch and menu-bar companion for agent runtimes, with original Pixel character art and a generic read-only connector architecture. It works standalone with a mock runtime; Pixel HQ and Paperclip are optional.

**Status: local development Alpha. Not a public release, not merged to main, not security- or human-QA-approved.**

## Current integrated Alpha

- Native compact notch, hover snapshot, detail panel, menu-bar fallback and original animated character.
- Four tabs: Overview, Agents, Usage, Activity. Command-1/2/3/4 navigation, shared tab state and Reduce Motion support.
- Optional read-only Paperclip GET connector: health, company selection, agents, issues/tasks, approvals, bounded recent runs and usage.
- Live Operations and Attention overview for confirmed running/queued/failed latest runs, company-wide approvals and reported monthly budget/context warnings.
- Agent search, Active filter and optional grouping by reported role (not inferred department); inspector with real model/provider/tokens/context, recent agent-ID-linked run history and structured assigned tasks.
- Collapsible read-only company tasks with local search and a searchable/dated Activity timeline with cached/stale labels.
- Optional credential-free **public GitHub CI panel** for up to three recent Actions workflow runs and open PRs. It is disabled until explicitly configured and does not affect Paperclip monitoring.
- Opt-in privacy-safe macOS notifications for newly observed approval or run-completion/failure transitions; in-app attention cards do not generate another push notification.
- Mac Settings for connector, company, presentation, notifications, and explicit Launch at Login in a final installed non-QA release. Temporary QA builds cannot register persistent login items.
- Optional energy conservation slows read-only Paperclip checks to 20 seconds in macOS Low Power Mode, with an ordinary refresh after wake.
- Optional, off-by-default local Focus timer with 25-minute focus, 5/15-minute breaks and pause/resume/reset; no account or stored session history.
- Optional, off-by-default read-only Battery & Power panel with actual macOS-reported charge/power state and no stored hardware identifiers.

Missing data is never guessed: unknown costs/context/assignees, run progress and complete run history are labeled unavailable. Live information is suppressed when the Paperclip feed is stale.

## Local development

Requires macOS 14+, Xcode 16+ and SwiftLint for strict quality checks. There are no third-party Swift dependencies.

    swift test -Xswiftc -warnings-as-errors
    scripts/quality/check.sh --base origin/main
    swift run PixelCompanion

For Paperclip, set a private reachable base URL and company in Settings. Local SSH forwarding at http://127.0.0.1:3100 continues to work; remote servers require HTTPS. Never store credentials or secrets in URLs. The connector **only sends GET**. It cannot approve, send chat, deploy, start/stop an agent or execute commands.

See docs/BUILDING.md, docs/ARCHITECTURE.md, docs/CONNECTORS.md, docs/QA_TEST_PLAN.md and docs/QUALITY_GATE.md.

## What is not complete

This Alpha is not the full agreed v1. Remaining work includes deeper company/department/task/run/log views where structured data exists, authenticated/private GitHub and VPS/HomeLab/deployment connectors, extended original character behaviors, Mac accessibility/energy/Shortcuts refinement, and secure Atlas chat and approval/control flows gated by reviewed identity, Keychain/Secure Enclave/Touch ID and authenticated private APIs.

The full v1 tracker is https://github.com/GrimClawBot/Pixel-Companion/issues/48. Greptile final-SHA review, independent human security approval for sensitive changes, real Mac UI verification, official signing/notarization and public releases are separate gates. Green automated tests do not satisfy them.
