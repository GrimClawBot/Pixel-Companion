# PC-054 — Paperclip transport hardening review

This is a DRAFT, unmerged security hardening change based on the PC-053 pre-merge audit. It does not change Paperclip production, the connected Mac's existing network tunnel, Codex/Claude hooks, or any live credentials.

## Findings and proposed corrections

1. Inherited system session state: the original Paperclip service defaulted to the system shared URL session, which can carry shared cookies, credentials and caching behavior. The proposed default is a dedicated ephemeral URLSession, with cookies disabled, no credential storage, no disk cache and normal HTTP GET behavior.
2. HTTP redirects: the previous default could automatically follow 3xx responses from the configured endpoint. For the supported localhost SSH-forward, a redirect can escape the validated tunnel boundary. The new delegate declines all redirects; 3xx remains an HTTP error rather than a connection to another host.
3. Dynamic endpoint path segments: server-returned company IDs enter Paperclip API URLs. The proposed builder permits only unreserved ASCII characters in nonempty segments and rejects dot/dotdot segments, percent encoding, question marks, fragments, empty segments and backslashes. This preserves ordinary UUID IDs and fixed API keywords but prevents path/query interpretation.

## Tests and release gates

Focused XCTest coverage validates the private default session configuration, redirect refusal, cookie-free requests even with an injected test session, ordinary API paths, unsafe path rejection and preservation of HTTPS origin and subpath.

Existing read-only Paperclip tests, local SSH-forward support and remote HTTPS validation are intended to remain unchanged. GitHub CI must pass at the exact head commit, and a local Mac quality gate plus a real Paperclip connection refresh are still needed before replacing the installed QA52. Green CI is not independent reviewer approval.

No merge or public release is authorized. This is an internal review finding with a proposed fix, not an independent third-party security audit. Broader PC-053 dependency review, VoiceOver, live-window QA and release notarization remain OPEN.
