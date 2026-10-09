# PC-071 — Source-verified agent reporting hierarchy

Paperclip's documented agent payload includes `reportsTo`, a manager **agent ID**
in the selected company. This Alpha adds a read-only **Reporting** layout in
the Agents tab alongside the original List and By role options.

## Data provenance and UX

- `PaperclipAgentResponse.reportsTo` is optional and independently decoded.
  `AgentSessionSnapshot.managerAgentID` carries that **structured source ID**
  across the existing GET-only connector. No extra endpoint or privilege.
- Reporting uses only live agent rows that are actually visible in the current
  agent filter. A missing, filtered-out or invalid parent is NOT substituted
  with a role, title, CEO guess or department guess.
- Acyclic, fully represented parent chains are shown indented. Every agent
  remains selectable through the existing inspector; when a verified manager
  is present, the inspector offers a **Reports to [agent]** navigation link.
- An absent manager ID means **no manager reported**, not an assertion of CEO
  or department leadership. Broken links are labeled **Manager not in this
  view**; loops are labeled **Reporting cycle not verified**. Malformed
  source IDs cannot grant a navigation path.
- Only four visual indentation levels are used at narrow widths; reporting
  depth can be deeper internally. By role still groups reported role labels;
  it does not represent departments.
- Snapshot freshness remains a prerequisite for directory and inspector.
  A reorganization is shown only after the next actual fresh source refresh.

## Evidence and tests

The agent-list response's `reportsTo` field is described in the upstream
Paperclip Agents API reference:
https://docs.paperclip.ing/reference/api/agents/

Pure Swift/XCTest cases check nested reporting, sibling ordering, same role
but different reporting, absent and filtered managers, cycles/self-reference,
broken grandparent chain, duplicate/empty IDs, no agents, and manager
navigation. Decoder tests cover `reportsTo` present, null, missing, or a
wrong JSON type.

For native human Mac acceptance, verify the List/By role/Reporting selector in
360pt and 440pt layouts, keyboard/VoiceOver navigation, search and Active
filter, manager inspector navigation/back, missing managers, split hierarchy,
live updates/reorganizations and stale/disconnected feed. Never infer a
department or a security permission from the reporting tree.

**Out of scope:** verified departments, cross-company authority,
backend-authenticated approvals, org mutations, chat, raw logs, server
configuration and live backend deployment. All remain human/security gated.
This work is source-only on a draft stacked PR; installed QA61, protected
`main`, Login Items and Paperclip production are unchanged. 
