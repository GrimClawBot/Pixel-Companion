# PC-083 — Optional generic infrastructure report (read-only Alpha)

## Actual capability and limitations

This is a **working local JSON report reader**, not remote host
discovery, a managed VPS credential, or authenticated HomeLab monitoring.
It is available to anyone using the standalone public Pixel Companion app,
without requiring Pixel HQ or any special organization or service.

Go to **Settings → Connections → Infrastructure · optional local JSON**,
enable the feature and explicitly select a JSON status file published by
a producer you trust. No file path or telemetry is persisted. Disabling
disconnects and immediately clears the report; the file must be chosen
again next launch. The macOS app **never contacts hosts, opens SSH,
makes WAN requests, installs software, or changes a deployment**.

The existing reviewed `LocalAgentFeedFileReader` reads only the
selected regular file, rejects final-file symlinks, and has a hard
64 KiB limit. Polling is at most every 15 seconds while enabled.
The schema parser is strict: version 1; 0–8 unique ASCII host IDs;
host labels have control/bidi characters removed; timestamps must be
ISO 8601 and no more than 30 seconds ahead of the Mac clock.

The Overview panel displays CPU %, RAM/disk used proportions, Celsius,
receive/transmit bytes per second and deployment health **only if
the source explicitly provides them**. No unreported fields are
fabricated or estimated. RAM/disk used and total must both exist
and be nonnegative/consistent. Malformed values invalidate the whole
report; no previous healthy readings remain visible.

A host is *recently reported* only while its timestamp is within
120 seconds of the Mac clock. Its metrics and deployment status are
**withheld** when the report becomes stale, with an explicit historical
message. Even a fresh report is **source-reported, not independently
attested as host health**. Never interpret a report as authorization
to restart a service or approve a change.

## Example schema (illustrative only — not live telemetry)

```json
{
  "schemaVersion": 1,
  "hosts": [
    {
      "id": "example-node-1",
      "name": "Example compute node",
      "observedAt": "2026-10-09T12:00:00Z",
      "cpuPercent": 24.5,
      "memoryUsedBytes": 8589934592,
      "memoryTotalBytes": 17179869184,
      "diskUsedBytes": 107374182400,
      "diskTotalBytes": 214748364800,
      "temperatureCelsius": 49.3,
      "receiveBytesPerSecond": 24000,
      "transmitBytesPerSecond": 15000,
      "deployment": { "name": "example-app", "state": "healthy" }
    }
  ]
}
```

The producer must update `observedAt` with actual source collection
time. Values above are **illustrations**, not actual Pixel HQ or
user-device measurements. Supported deployment values: `healthy`,
`degraded`, `failed`, or `unknown`. Any numeric metric and deployment
may be omitted if not reported. There is intentionally **no host
address, token, internal endpoint, command, log, tool call, or
personal credential field** in this contract.

A local producer may itself collect remote metrics over a separately
approved secure private connection, but that collection is **outside**
Pixel Companion's authority. It needs its own authentication, routing,
authorization, logging and threat review. This feature does not create
a trusted private VPS/HomeLab API or a network/plugin sandbox.

## QA83 local Mac acceptance

The branch includes a new isolated `--qa-number 83` installer option,
and actual no-write variant checks. It creates
`~/Applications/Pixel Companion QA Update 83.app` without replacing
existing QA82. The source build uses a private temporary Info.plist,
offline ad-hoc signing, exact QA marker validation, and real macOS
Login Items disabled for QA bundles.

After exact-head native CI passes, the owner or approved remote-control
connection can build the new app from a clean source clone, preserving
the current installed QA82 while compiling:

```bash
git clone --depth 1 --branch pc-083/opt-in-local-infrastructure-evidence \
  https://github.com/GrimClawBot/Pixel-Companion.git \
  "$HOME/Developer/Pixel-Companion-QA83"
bash "$HOME/Developer/Pixel-Companion-QA83/scripts/qa_preview_macos.sh" \
  --qa-number 83 --no-open
```

Confirm Settings → General displays **0.1.0 (build 83)** and
**QA Update #83**. Test the opt-in flow using a deliberately prepared
local report, stale timestamp, malformed/out-of-range values, duplicate
host IDs, removed file, no hosts, and disabled state. Verify no
unauthorized network call, persistence, start-at-login change or fake
green status. Check VoiceOver, keyboard, 360pt/440pt widths, reduced
motion, menu-bar fallback and existing Agent/Task/Run and other utilities.

Once the replacement app is verified/signed and actually running,
the previous **QA82** bundle may be moved into macOS Trash under the
owner's existing older-QA cleanup permission. Never permanently delete
Trash or source repositories, settings or unrelated apps.

## Required gates

Tests do not prove source attestation, actual host health or Mac UI
acceptance. Native Swift/Python/lint/config/security CI, Greptile
current-SHA technical review, independent GitHub human approval and
Mac human QA remain separate. This is a DRAFT stacked PR; no protected
main merge, notarization, public binary or network privilege granted.

## QA84 follow-up: menu-bar parity fix

During PC-083 acceptance the menu-bar popover was found to omit the
optional infrastructure monitor, although the notch detail supplied it.
The menu-bar host now injects the same monitor into the shared detail
composition, and native XCTest prevents a future omission.
Build the new **QA84** from a clean checkout of this exact reviewed commit,
using `scripts/qa_preview_macos.sh --qa-number 84 --no-open`. Keep the
working QA83 app unchanged until QA84 code-signing, exact-commit checks,
local smoke tests and launch verification complete. Only then may the
verified, stopped QA83 bundle be moved to recoverable Trash.

Greptile technical review and independent human approval are still
required for merge; Mac verification does not satisfy those gates.
