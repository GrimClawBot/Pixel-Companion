# PC-064 — Preserve valid Paperclip runs with malformed optional context metrics

Greptile's historical Alpha review observed a P2 compatibility issue:
synthesized Decodable for optional usageJson.contextUsedTokens and
contextWindowTokens would reject a whole run when either optional metric
had a non-integer type (such as a string or object). Paperclip's
lossy-array decoding then discarded the run, hiding otherwise valid
agent run status and usage.

PaperclipHeartbeatRunResponse.Usage now implements Decodable with
existing required and ordinary optional fields preserved under normal
type-checked decodeIfPresent, while only the two optional context
measurements use tolerant best-effort integer decoding. An untrusted
wrong type produces nil for that metric, NOT a default numeric value
and NOT a guessed context size.

Regression tests decode a valid running record with well-formed
input, output, and cached token counts plus malformed context metrics;
verify the entire run and mapping remain available; and separately
verify a non-string required agentId still throws as before.

No Paperclip egress, credentials, server state or provider settings are
altered. This strictly additive compatibility change is stacked on
PC-063 in a draft PR. Keep QA58 until the exact new code is signed,
locally launched and verified; there is no automatic main merge,
human approval, notarization or public release. Greptile can audit
the exact head, but a bot verdict never substitutes for the
independent protected-branch approval held until owner request.
