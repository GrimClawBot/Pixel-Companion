## Change

<!-- What and why. Link the Paperclip issue (PIX-…) and GitHub issue. Keep PRs small and single-purpose. -->

## Quality gate (docs/QUALITY_GATE.md)

- [ ] `scripts/quality/check.sh --base origin/main` → `RESULT: PASS` on macOS (paste summary below)
- [ ] `scripts/quality/greptile_review.py --base origin/main` → verdict `pass`, or `human_review_required` with a named human reviewer
- [ ] Every blocker/major Greptile finding fixed in a follow-up commit, then native checks **and** Greptile rerun
- [ ] Tests added/updated for changed behaviour
- [ ] Sensitive surface? (auth, secrets, CI, dependencies, entitlements/Info.plist, public API) → security/human reviewer: @…
- [ ] QA acceptance plan handed off (macOS runtime/UI)

<details><summary>Native check summary</summary>

```
paste the "Quality gate summary" block
```
</details>

<details><summary>Greptile report</summary>

```json
paste quality-reports/greptile-<sha>.json (verdict + findings)
```
</details>
