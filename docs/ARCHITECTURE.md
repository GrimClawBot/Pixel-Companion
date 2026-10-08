# Pixel Companion architecture (integrated read-only Alpha)

Pixel Companion is a generic standalone macOS front door, not the Pixel HQ server. The public core contains no private Pixel HQ organization, backend credentials, server addresses, agent commands or third-party character assets. Coucou, AgentPeek and SuperIsland inspire character, agent visibility and extensibility respectively; no dependency on their code/assets or silent-approval behavior is introduced.

## Data flow

1. Local non-secret SettingsStore selects None, deterministic MockConnector, or the optional Paperclip connector.
2. The Paperclip adapter uses GET-only URLSession requests for health, company, dashboard, agents, issues, approvals, recent heartbeat runs and live runs. It maps narrow DTOs into sanitized read-only models.
3. Connector state is synchronized, with generation fencing for telemetry and bounded recent-run data. Snapshot capture produces the immutable ConnectorSnapshot.
4. AppModel computes recent successful-sync freshness and mood, and supplies views for native notch/menu bar, Live Operations, Agents, Usage, Activity and Settings.
5. Existing opt-in notification detector deduplicates newly observed approvals and run outcomes and passes privacy-safe generic banners to macOS. In-app Attention cards are a separate visual digest and never submit duplicate OS notifications.

The public connector protocols support optional AuthProvider, ActivitySource, ApprovalProvider, UsageProvider, AgentSessionSource, TaskSource, and read-only ChatBackend capabilities. New providers can be added behind these interfaces without requiring a Pixel HQ installation.

A separately configured optional public GitHub CI side source uses a sanitized owner/repo identifier and fixed api.github.com HTTPS GET endpoints for bounded public Actions runs and PRs; no account, tokens or arbitrary network URLs. Its three-minute polling and failure state are independent of Paperclip; private repos, CI mutation and privileged GitHub integrations are not supported by this source.

Run association is based on structured Paperclip agentId; assigned tasks use structured assigneeAgentId. Never infer ownership from free-form issue text, or treat input/output token totals as context occupancy. Bounded recent runs are not a full audit log. An unknown or delayed backend refresh cannot be shown as confirmed current information: agent detail, tasks, operations and warnings are suppressed until the feed is live. Existing cached event history is labeled.

## Native behaviors

NSScreen notch geometry determines notch versus menu bar fallback. SwiftUI provides original Pixel character, compact snapshot, four-tab detail, agent/task/run drilldown and shortcuts. Mac Reduce Motion disables tab transitions and loading spinners. Launch at Login uses the explicit ServiceManagement OS API only on an installed non-QA app; no custom launch agents. Notifications require opt-in and user/macOS permission.

## Security boundaries

- Paperclip non-loopback URLs require HTTPS. HTTP loopback supports an existing user-managed localhost SSH forward only; URL-embedded credentials/query/fragment are refused.
- No source-side API can approve, reject, deploy, send commands, run SSH or mutate Paperclip. UI Read-only is not a substitute for a trusted backend authorization layer.
- Future private connectors, Touch ID/Keychain/Secure Enclave, device trust, Atlas chat, approvals and other controls need explicit scoped APIs and human security review. No credentials or hardcoded Pixel org details in the OSS repo.
- Build/entitlement/auth/public API changes require a named human/security review even when GitHub Actions succeeds. A bot status without an actual submitted review is not approval.

For human interaction acceptance and release holds see docs/QA_TEST_PLAN.md and docs/QUALITY_GATE.md.
