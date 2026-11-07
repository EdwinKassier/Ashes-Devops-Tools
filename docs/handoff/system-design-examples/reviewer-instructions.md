# Instructions for every walkthrough reviewer

Review one walkthrough in a system-design interview study library. The library is grounded in this Terraform AWS+GCP landing zone.

- **Read-only.** Do not edit, commit or dispatch subagents.
- **Web access.** WebSearch and WebFetch are allowed. Use them.

## Inputs (this directory)
- `task-<N>-brief.md`
- `task-<N>-report.md`
- the review package `review-*..<sha>.diff` named in your dispatch
- `writer-instructions.md`: the writer's rules, which are your checklist
- `global-constraints.md`
- the spec: `docs/superpowers/specs/2026-11-07-system-design-examples-design.md` (your question's entry in "The library" lists the required deep dives)
- `examples/system-design/00-primer.md`: the walkthrough must link to it, not restate it

## The user's anti-goals are your rubric
1. **Overly complex.** Does the two-minute answer stand alone as a strong interview opener? Read only that section and judge. Are the deep dives focused, at 2 or 3? Are the diagrams legible, at no more than 15 nodes?
2. **Not correct.** This is the priority.
   - Fetch at least **6** of the cited URLs and confirm each figure or claim.
   - Check the estimates' arithmetic.
   - Check every snippet argument name against the HashiCorp Registry docs for google `~> 8.0` and aws 6.x. Provider binaries are also cached in `/private/tmp/claude-501/tfcache`.
   - Check every repo claim (module, input, config key, output, file:line) against the repo.
   - Uncited drifting facts are findings.
3. **Not usable as a study guide.** Does the estimates section drive the later choices? Is the trade-off table a real decision record? Do the study aids give crisp follow-up answers?

## Also check
- All 13 `##` headings are present, exactly titled and in order. There is one `#` H1.
- The required deep dives from the spec entry are all present.
- The word count is 3,000–6,000.
- Raw-resource snippets follow the primer's #conventions: naming, CMEK, VPC tier, tag/label casing per the AWS tag policy, per-component identity, and a gap note. GCP region-scoped resources use `local.env_config.region`.
- The runbook follows the format of `docs/runbooks/*.md`.

## Output
- "Spec: ✅/❌", with gaps.
- "Quality: Approved / Needs fixes", with findings rated Critical, Important or Minor. Give each a line reference.
- For every incorrect fact, give the correct value and its source.
- End with a final line: "Verdict: Approved" or "Verdict: Needs fixes".
- Keep it under 500 words.
