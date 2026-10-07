# Connector interfaces

Pixel Companion shows the state of an agent runtime. It does not know which runtime: everything
service-specific sits behind the protocols in
[`Sources/PixelCompanionCore/Connector/ConnectorProtocols.swift`](../Sources/PixelCompanionCore/Connector/ConnectorProtocols.swift).
The app works with no connector at all (it shows the offline character), so Pixel HQ, Paperclip or
any other backend is an optional plug-in, never a requirement.

## Rules for every connector

- **Read-only.** Connectors report state. None of the protocols has a method that approves, sends,
  deploys or otherwise changes anything on the backing service, and implementations must not add one.
- **No credentials in the app.** `AuthProvider` reports a status (`notRequired`, `unauthenticated`,
  `authenticated(displayName:)`) and nothing else. No tokens, passwords, or keychain access.
- **No hard-coded endpoints or org structure.** Anything a real connector needs to find its service
  is configuration, added with its own reviewed change.
- **Main thread.** The app calls connectors from the main actor. `refresh()` must return quickly; a
  network-backed connector refreshes in the background and serves cached values here.

## Protocols

| Protocol           | Answers                                         | Required members                         |
|--------------------|-------------------------------------------------|------------------------------------------|
| `Connector`        | Who are you, are you connected, what can you do | `id`, `displayName`, `connectionState`   |
| `AuthProvider`     | Is the user identified?                         | `authStatus`                             |
| `ActivitySource`   | What is the agent doing?                        | `currentActivity`, `recentActivity(limit:)` (newest first) |
| `ApprovalProvider` | What is waiting on a human?                     | `pendingApprovals()`                     |
| `UsageProvider`    | How much of the quota is used?                  | `currentUsage()`                         |
| `ChatBackend`      | What was said recently?                         | `recentMessages(limit:)` (oldest first)  |

`Connector` exposes each capability as an optional property (`auth`, `activity`, `approvals`,
`usage`, `chat`). A protocol extension defaults all of them to `nil`, along with `lastError` and a
no-op `refresh()`, so the smallest valid connector is:

```swift
final class StatusOnlyConnector: Connector {
    let id = ConnectorID(rawValue: "example.status")
    let displayName = "Status only"
    var connectionState: ConnectionState = .connected
}
```

The UI never talks to a connector directly. `ConnectorSnapshot(capturing:)` reads every capability
once into an immutable value and fills missing capabilities with empty data. The character and all
views work from that snapshot.

## MockConnector

`MockConnector` is the only implementation in this release. It replays a `MockScript`, a looping
list of `MockStep`s (activity kind and title, pending approvals, usage, an optional chat line):

- Each `refresh()` advances one step, but only while `simulatedConnectionState == .connected`.
  Settings change that state to preview connecting, disconnected and error.
- Every value is a pure function of the tick count and the script. Timestamps come from
  `startDate + tick × stepInterval`, not the wall clock, so a script replays identically in tests
  and on screen.
- `advance(by:)` and `reset()` drive it directly from tests or demos.

Built-in scripts: `MockScript.demo` cycles through every character mood (idle → working →
waiting for approval → working → error → working → idle), and `MockScript.quiet` stays idle.
Custom scripts are plain values:

```swift
let script = MockScript(steps: [
    MockStep(kind: .running, title: "Compiling"),
    MockStep(kind: .running, title: "Needs sign-off", pendingApprovals: ["Ship build 12"]),
    MockStep(kind: .failed, title: "Tests failed")
])
let connector = MockConnector(id: ConnectorID(rawValue: "mock.custom"), displayName: "Custom", script: script)
```

## PaperclipConnector

`PaperclipConnector` is the first real runtime connector. It is intentionally read-only and only
uses GET requests for health, company discovery, dashboard summary, agents, issues, and approvals.

- The Paperclip base URL and company selection are local `UserDefaults` settings.
- No endpoint, company ID, credential, Pixel HQ org detail, adapter command, environment value, or
  secret is compiled into the public repository.
- Network work happens asynchronously. `Connector.refresh()` only starts/coalesces a refresh and
  the UI reads the most recent synchronized cache.
- Agent payloads are decoded into narrow DTOs: only identity/status/timestamps needed for generic
  companion activity are read. Adapter configuration and other runtime internals are ignored.
- Multiple companies can be discovered before a company is selected. A single active company may
  be selected automatically in memory.
- Approval data is display-only. There are no approve/reject/send/deploy mutation APIs in the
  connector.

For local/private deployments, point Settings at the URL that is reachable from the Mac (for
example a user-managed tunnel or private network address) and select the desired company.

## Adding a real connector

1. Implement `Connector` and whichever capability protocols the service supports, in a new file or
   module. Keep service details (endpoints, payloads) inside it.
2. Add a `ConnectorID` and a `ConnectorOption` to `ConnectorRegistry` so it appears in Settings, and
   build it in `ConnectorRegistry.makeConnector(id:connectionState:)`.
3. Add tests that the connector maps service states to `ConnectionState` and never mutates anything.
4. Anything involving sign-in or stored secrets is a sensitive change under
   [QUALITY_GATE.md](QUALITY_GATE.md) and needs a named security reviewer.
