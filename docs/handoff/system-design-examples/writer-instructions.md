# Instructions for every walkthrough writer (Tasks 3–21)

You are writing one walkthrough in a study library for system design interviews. The library is grounded in this Terraform AWS+GCP landing zone. The reader is an engineer preparing for an interview. They study each walkthrough as a deep reference, rehearse from the two-minute answer, and may carry the design into this repo's Terraform.

## Read first
1. Your task brief. It gives your file, your title, and the shared steps.
2. `global-constraints.md`, in this directory.
3. The spec: `docs/superpowers/specs/2026-11-07-system-design-examples-design.md`. Read in full the sections on the Walkthrough template, the "Build it here" conventions, the Correctness process, the "Resolved after the builder check" section, and YOUR numbered entry in "The library". That entry lists the deep dives you must cover.
4. `examples/system-design/00-primer.md`. Link to its anchors and never restate them. The anchor slugs are frozen: `#interview-framework`, `#estimation-cheat-sheet`, `#aws-gcp-service-map`, `#how-this-landing-zone-anchors-a-design`, `#conventions`, `#data-zones`, `#vpc-tier-placement`, `#how-to-read-a-walkthrough`. The primer may also have sub-anchors; check its headings.

## Rulings in effect
These come from the ledger.
- **Headings.** Use exactly the 13 template headings as `##`, with the exact titles listed in global-constraints. Put everything else at `###` or below. The check is `grep -c '^## '` == 13. Your file has an `# <Title>` H1 at the top.
- **Shared vocabulary.** Data zone names (raw, curated, serving) and VPC-tier placement come from the primer's `#data-zones` and `#vpc-tier-placement`. Cite them; do not redefine them.
- **GCP CMEK.** The repo has no workload CMEK output on GCP. GCP snippets use `module "workload_cmek"` (source `modules/gcp/governance/kms`) in `gcp-workload-<env>`, referenced as `module.workload_cmek.key_ids["<component>"]`, with a one-line gap note. Follow the primer's #conventions exactly.
- **AWS CMEK.** The `workload_kms_key_arn` output of `aws-workload-<env>`, per the primer.
- **Tags and labels.** Follow the code, as the primer documents it: AWS `default_tags` (6 keys), GCP `default_labels` (4 keys).
- **GCP region.** Region-scoped GCP resources (Cloud Run, subnet attachments, KMS key rings) use `local.env_config.region` from `envs/gcp/workload`, never `local.region`.
- **GCP egress.** It is per-environment Cloud NAT, not inspected through the hub. Say so where egress matters.
- **Cross-references to later walkthroughs.** Leave them out for now. A final consistency task adds the links. You may name another question in prose ("see the adapter gateway walkthrough").

## Quality bar
These anti-goals are the user's own.
- **Not overly complex.** The two-minute answer stands alone. Each Mermaid diagram has at most 15 nodes. Do 2–3 deep dives done well, not ten done badly.
- **Correct.** Every drifting fact carries an inline link to official docs with "(checked 2026-11)": limits, quotas, provider arguments, latency and throughput figures, pricing models. Use WebSearch and WebFetch. Snippets use current provider argument names: google `~> 8.0` and aws 6.x. Verify each one against the HashiCorp Registry docs. Every repo reference must pass `make examples-refs`. If you can't verify something, write **verify before relying on**.
- **Usable as a study guide.** Use explicit numbers in the estimates. The trade-off table is a real decision record. Study aids give crisp follow-up answers.
- **Length.** 3,000–6,000 words, counted with `wc -w`.

## Lessons from earlier reviews (avoid these)
- **Capacity numbers.** Re-derive every capacity number after you pick headroom. A zone-loss scenario must still meet the load.
- **Copyable code.** Any SQL or pseudo-code a reader might copy must be correct:
  - Detect duplicates by checking the row count or `RETURNING`.
  - Conditional updates must check how many rows they matched.
  - Outbox column names: say which CDC tool's defaults they match.
- **Write limits.** Count every write path against provisioned or default limits, not only the obvious one.
- **TTL fields.** Check TTL and expiry field types against each store's docs. Firestore TTL needs a Timestamp; DynamoDB TTL needs epoch seconds.
- **Grants.** A grant on one service doesn't cover a caller. Check that every caller of an encrypted queue, topic or bucket has KMS on the key.
- **GCP subscriptions.** Raw Pub/Sub subscriptions need `expiration_policy { ttl = "" }`.

## Build it here
- Name the real roots and workspaces, and the apply order.
- Show `config/landing-zone.yaml` snippets using real keys (check them in `config/landing-zone.schema.json`).
- Show module calls with real inputs (check each module's `variables.tf`).
- Where no module exists, show raw resources that follow the primer's #conventions: naming, CMEK, VPC tier, tags/labels, and a per-component identity. Add a one-line gap note to each.
- Keep the whole section to about 150 lines of snippets.

## Runbook
Follow the format of the repo's `docs/runbooks/*.md`: detection signal, triage, mitigation, verification, follow-up. Cover the scenario's most likely serious failure.

## Verify, then commit
- `make links examples-refs`
- markdownlint: `pre-commit run markdownlint --files <your file>` if available, otherwise `npx --yes markdownlint-cli2 <file>`. Its `--fix` may renumber lists, so re-check them.
- `wc -w <file>` must be in range, and `grep -c '^## ' <file>` must equal 13.
- Commit only your file, by explicit path: `git commit --no-verify -m "docs(examples): <title>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- <file>` after `git add <file>`.
- Other writers are committing at the same time. If you hit index.lock, retry. Never amend, never push, never use `git add -A`.

Do not dispatch subagents. Write your full report to `task-<N>-report.md` in this directory. Include:
- the word count;
- the citations you fetched, as URL list counts;
- the repo modules and config keys you referenced;
- the gap notes you made.

Reply only with Status, commit SHA, a one-line verification summary, and concerns.
