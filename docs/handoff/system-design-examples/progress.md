# SDD ledger — plan: docs/superpowers/plans/2026-11-07-system-design-examples.md
Spec: docs/superpowers/specs/2026-11-07-system-design-examples-design.md
Branch claude/system-design-examples, base 95bff95

## Pre-flight scan
| Tasks | Shared file / interface | Producer → consumer | Finding |
|---|---|---|---|
| 1 → 2..22 | scripts/check-examples-refs.sh, `make examples-refs` | 1 produces gate; 2..22 run it | ok — 1 must land first |
| 2 → 3..21 | 00-primer.md anchors (#conventions, #estimation-cheat-sheet, #aws-gcp-service-map, #how-this-landing-zone-anchors-a-design) | 2 produces; walkthroughs link | ok — 2 must land before 3..21 |
| 2, 22 | examples/system-design/README.md | 2 writes index naming all 19 files; 22 checks titles match | ok — 2 writes index with planned file names before files exist → `make links` would fail in Task 2 |
| 12 → 13 | zone names raw/curated/serving | 12 defines, 13 (#11) cites | order conflict: #11 (Task 13) is written before #12 (Task 14) |
| 5 → 8, 20 | outbox pattern | #3 defines | ok (5 before 8, 20) |
| 6 → 21 | adapter pattern | #4 defines | ok |
| 16 → all | VPC-tier placement reference (#14) | every Build-it-here links #14 | order conflict: #14 is Task 16, written after Tasks 3–15 |
| 17 ↔ 18 | DR ladder → active-active | #15 links #16 | forward link only, ok if anchor fixed by name |
| each 3..21 | self-consistency | template 13 headings vs `grep -c '^## '` check | `grep -c '^## '` counts all ## headings; walkthroughs may need extra ##? spec mandates exactly 13 sections → ok if deep dives use ###|
| 1 | test vs code | fixture input `subnet_cidrs` exists on tiered-vpc | ok (verified var.subnet_cidrs) |
| 22 | — | consistency only | ok |
Ruling: Task 2's README index lists all 19 entries as plain text (title + planned filename in code font), not links; Task 22 converts them to links once every file exists — `make links` would fail on 19 dangling links in Task 2 — cost if wrong: one extra edit in Task 22
Ruling: forward references (to #12 zone names from #11, to #14 VPC tiers from earlier walkthroughs, to #16 from #15) are owned by the PRIMER: Task 2's primer defines the shared zone names (raw/curated/serving) and the VPC-tier placement rules under #conventions; walkthroughs link the primer, and #12/#14 elaborate without redefining. Task 22 adds the cross-links between walkthroughs — avoids reordering 19 tasks — cost if wrong: primer slightly longer
Ruling: walkthrough tasks 3–21 run up to 3 at a time (each writes exactly one new file; explicit-path staging; index.lock retry) — 19 serial long-form writes would take a day; disjoint files make concurrency safe (proven on prior plan) — cost if wrong: a commit retry
Ruling: walkthroughs use exactly the 13 template headings as `##`; deep dives and sub-parts use `###` or lower so the `grep -c '^## '` == 13 check holds — cost: none
Task 1: dispatched (base 95bff95, sonnet)
Task 2: dispatched (base 95bff95, opus) concurrent with Task 1 (disjoint files; examples-refs gate re-run at review)
Task 1: implemented 04f3b0f; review dispatched
Task 1: review Needs fixes (2 Important false negatives: heredoc brace depth, fence aliases) + minors → fix round 1 sent (new commit, no amend)
Task 1: fix round 1 committed 8d12b07; scoped re-review dispatched
Handoff: tracked copy at docs/handoff/system-design-examples/ (commit 5216619); draft PR #594 (stacked on #592 branch) — ledger synced+pushed after every update
Task 1: re-review Approved (all 6 addressed)
Task 1: complete (commits 04f3b0f, 8d12b07)
Task 1: minor (deferred): a heredoc inside a resource block containing literal `module "x" {` text is parsed as a module (contrived)
Task 2: implemented 4aae741 (anchors: #interview-framework #estimation-cheat-sheet #aws-gcp-service-map #how-this-landing-zone-anchors-a-design #conventions #data-zones #vpc-tier-placement #how-to-read-a-walkthrough); review dispatched (opus)
Ruling: primer anchor slugs are FROZEN (walkthroughs start now in parallel with the primer review; any primer fix must keep these slugs) — cost: none
Ruling: GCP workload CMEK convention = new module "workload_cmek" (modules/gcp/governance/kms) in gcp-workload-<env>, key ring <prefix>-<env>-cmek, referenced as module.workload_cmek.key_ids["<component>"], with a gap note — repo has no workload CMEK output on GCP — cost if wrong: walkthroughs show a key the repo doesn't yet create (flagged as gap)
Ruling: tags/labels follow code (AWS 6 keys, GCP 4) not the spec's "four keys" wording; GCP egress described honestly as per-env Cloud NAT, not hub-inspected — code is truth — cost: none
Task 2: out-of-scope repo issues logged (not this plan): org cmek_key_names description says full IDs but returns short names; CLAUDE.md lists google ~> 7.0 (repo is 8.x); aws-landing-zone.md links a dead anchor in adding-a-cloud.md
