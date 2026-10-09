# PC-065 — Cancel pending Launch at Login registration

The earlier Launch at Login toggle treated SMAppService.mainApp.status
requiresApproval as Off. That is inaccurate: macOS has a registered login
item whose activation is awaiting system approval. Since the UI was already
Off, switching it Off did not call SMAppService.mainApp.unregister().

## New behavior

- requiresApproval is displayed as **On — Pending approval** (not as
  enabled/approved). System Settings → General → Login Items remains the
  authority for the actual approval decision.
- Turning the switch Off or selecting **Cancel pending login request**
  unregisters the pending item through Apple's public ServiceManagement API.
- Toggling On while already registered/pending never re-registers.
- A fresh macOS status read precedes each explicit user action. Changes
  made outside Pixel Companion are respected; Refresh updates the view.
- A failed unregister leaves the switch in its still-pending state and
  presents a useful error; it never implies the operation succeeded.
- Temporary ad-hoc QA builds and swift run remain unsupported for login
  registration. They cannot register/unregister login items through this
  UI, and still do not persist any login preference in UserDefaults.

## Verification

ServiceManagement is behind a small main-actor service protocol. A fake
service tests all transitions without touching macOS login registrations:
requiresApproval -> disabled; explicit cancellation; pending On idempotence;
macOS external changes; normal enabled/disabled transitions; cancellation
failure and unsupported QA rejection.

The release-only startup toggle is not exercised in disposable QA packages
because QA intentionally prohibits registration. A final installed-release
macOS acceptance step should verify the actual user authorization flow:
request, observe Pending, cancel, and optionally approve under System
Settings; this requires deliberate user interaction and cannot be simulated
by silently editing real Login Items.

This draft remains additive to the accepted code stack. Do not merge to
protected main or publicly release without separately authorized human
review and owner approval. Greptile helps find flaws but cannot replace
required independent GitHub approval. No changes to Paperclip production,
Codex/Claude provider configs, Sky notifier forwarding or user login items
occur during tests.
