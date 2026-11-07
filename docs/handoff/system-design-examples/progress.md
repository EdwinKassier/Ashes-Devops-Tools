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
Writers: shared instructions at .superpowers/sdd/2026-11-07-system-design-examples/writer-instructions.md (opus writers, opus/sonnet reviewers)
Tasks 3,4,5: dispatched in parallel (base 5ff6820)
Task 2: review Needs fixes — Important: GCP canonical snippet uses local.region; must be local.env_config.region (subnet + CMEK key must match service region) at 00-primer.md:778-810. Minors: Cloud SQL grant is project-level w/ IAM condition (app-services main.tf:433-451); add AWS org tag-policy casing (CostCenter/Environment/Owner); latency table add SSD 4KB ~100µs + cross-AZ RTT ~1ms; split units row; service map drop dup Logs/DR rows + cite SCP/RCP docs for data perimeter; mermaid GCP chain missing gcp-projects; data zones add naming line + workload CMEK → fix round 1 pending
Tasks 3,4,5: writers hit the 5-hour usage limit (resets 18:10 Europe/London); partial work unsaved to git — resume by SendMessage after reset, or re-dispatch fresh writers (files may be partially written in working tree: check `git status examples/system-design`)
Task 2: fix round 1 sent to primer implementer (18:12)
Tasks 3,4,5: writers resumed after limit reset (18:12), told GCP region = local.env_config.region
Ruling: GCP region-scoped resources in all snippets use local.env_config.region (not local.region) — subnet and CMEK must match the service region — cost: none
Task 2: fix round 1 committed f342691; scoped re-review dispatched
Task 2: re-review Approved (all 8 addressed; anchors intact)
Task 2: complete (commits 4aae741, f342691)
Task 2: minor (deferred): data-zones bullet calls workload_cmek "the per-environment key on GCP" — should note it is a convention/gap (see CMEK source)
Task 4: implemented d842499 (5959 words, 13 headings, gates green; ~164 snippet lines); review dispatched (opus)
REPO GAPS (out of scope, for known-gaps / follow-up): envs/aws/workload doesn't pass queue_kms_key_arn (SQS-managed encryption); AWS workload CMK key policy lacks events.amazonaws.com; GCP environment stage doesn't pass pubsub_kms_key_name; GCP app-services pubsub option creates only a pull subscription (request-billed Cloud Run can't drain)
Task 6: dispatched (opus) — writers in flight: 3, 5, 6; reviewer: 4
Task 3: implemented 50e9fb3 (5973 words; 157 snippet lines); review dispatched (opus)
REPO GAPS: modules/aws/network/load-balancer has no idle_timeout input (ALB 60s default); app-services sets no ulimits (Fargate nofile 65535 caps ~60k sockets/task); no modules for ElastiCache, DynamoDB, Memorystore Valkey, GCP service connection policy
Task 5: implemented bfbafca (5967 words; outbox anchor 03-microservices-sync-async.md#the-transactional-outbox); review dispatched (opus)
REPO GAPS: app-services queue policy can't admit SNS (single policy); workload KMS key policy needs sns.amazonaws.com; AWS hub central endpoints lack SNS/SQS; GCP app-services one subscription per service on own topic; no cpu_idle exposed; topics take no schema_settings
Task 3: review Needs fixes (Important: zone-loss headroom 30%/260 → 50%/300) + minors (CloudFront 30s, NLCU figure, pricing markers) → fix round 1 sent
Task 5: review Needs fixes (4 Important: Debezium column defaults claim wrong; consumer SQL dedupe/decrement bug; pubsub subscription missing expiration_policy; Token Creator condition is service-agent date not project age) + 4 minors → fix round 1 sent
Task 4: review Needs fixes (3 Important: notify-api lacks KMS grant once queue CMEK on; DynamoDB WRU undercount 51k>40k; Firestore TTL needs Timestamp) + minors → fix round 1 sent
Task 3: fix round 1 committed fe22015; scoped re-review dispatched
Task 3: re-review Approved
Task 3: complete (commits 50e9fb3, fe22015)
Task 3: minor (deferred): NLCU 100k figure lacks its own inline citation
Task 9: dispatched (opus); writer-instructions gained 'Lessons from earlier reviews'
Task 5: fix round 1 committed 01f0910; scoped re-review dispatched
