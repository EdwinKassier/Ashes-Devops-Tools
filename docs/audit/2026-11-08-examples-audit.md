# Examples audit (2026-11-08, branch `claude/system-design-examples-cont` at 1feb951)

## Summary

The examples are in good shape overall, but 5 Critical findings would break a copy-paste or mislead a reader, and 27 Important findings need a fix.

- **System-design library** (`examples/system-design/`, PR #594): strong on completeness and teachability, weakest on correctness of a few design details. Mean scores out of 10: correctness 7.7, completeness 8.6, best practice 7.9, teachability 8.1. Two Critical findings, 18 Important.
- **Other examples** (`examples/*` outside the library, and the module `examples/` directories): the presets, `dev.tfvars.example` and `app-services` overlays are excellent. The delivery workflows, the `aws-landing-zone` tfvars and READMEs, and the `vpc-sc` example are out of date or broken. Three Critical findings, 9 Important.
- **Mechanical sweep:** 101 of 104 Terraform example directories pass `terraform init` and `terraform validate`. The other 3 fail because they pin a release tag that does not exist yet.

No finding was refuted in verification. 22 of the original Important findings were downgraded to Minor.

## Status of the fixes (2026-11-08)

All 5 Critical and all 27 Important findings are fixed, in three PRs plus the v0.1.0 release. Critical 3 (the `?ref=v0.1.0` examples) closed when v0.1.0 was published on 2026-11-08: all three examples now pass `terraform init` and `validate` against the tag, and CI validates them again.

- **System-design library:** EdwinKassier/Ashes-Devops-Tools#594 (branch `claude/system-design-examples`). Ten walkthroughs fixed (01, 03, 06, 09, 11, 12, 13, 15, 17, 19), including both library Critical findings. An independent review confirmed every finding fixed and found no regression; its Minor notes were also cleared.
- **Runbook OU key:** EdwinKassier/Ashes-Devops-Tools#596 (`docs/runbooks/aws-add-account.md` now writes `ou: Workloads/Prod`).
- **Everything else:** the PR that adds this report (branch `claude/examples-fixes`):
  - the dead `aws.app_ingress_mode` and `aws.bootstrap_image` schema keys removed, and the example YAML comment moved under `workload:`;
  - the ECS, GKE and Cloud Run delivery workflows reworked (app-services output contract, least-privilege GKE RBAC, actions SHA-pinned at current majors), and the matching GKE advice in `docs/guides/deploying-a-service.md`;
  - `examples/aws-landing-zone` rewritten around `config/landing-zone.yaml`, with every tfvars key checked by a mock plan;
  - the `vpc-sc` ingress rule and log filter, and the `kms` and `workloads` READMEs, corrected;
  - a header note on the three `?ref=v0.1.0` module examples (mitigation only; the fix is cutting the v0.1.0 tag);
  - a `basic` example for each of the 25 modules that had none, each passing `terraform init` and `validate`.

The v0.1.0 release is published, and CI no longer skips the tag-pinned examples.

## How this audit was done

- **Scope.** Everything under `examples/` (the system-design library: README, primer and 19 walkthroughs; plus `app-delivery`, `app-services`, `aws-landing-zone`, `cloud-armor`, `cloud-storage`, `kms`, `presets`, `vpc-sc`, `workloads`, `dev.tfvars.example`), and all 104 directories under `examples/` and `modules/**/examples/` that hold Terraform.
- **Rubric.** Each file was scored 1-10 on four dimensions:
  - **Correctness:** facts against official docs, arithmetic, Terraform validity, copyable SQL and code, repo claims.
  - **Completeness:** required content present, both clouds covered, runbooks complete.
  - **Best practice:** what a senior engineer would recommend in 2026, including security, reliability, cost and Terraform idiom.
  - **Teachability:** the two-minute answer stands alone, estimates drive decisions, and the prose is plain and readable.
- **Independent audits.** Seven auditors ran in parallel. Six covered the library (three or four files each) and one covered the other examples plus 12 sampled module examples. Auditors were told not to read earlier review notes. Together they fetched more than 120 official doc pages, ran `terraform validate` on the extracted snippets against aws 6.72.0 and google 8.10.0, validated every YAML block against `config/landing-zone.schema.json`, ran mock plans of every tfvars and preset file, and ran SQL on PostgreSQL 17.
- **Verification.** Every Critical and Important finding went to an adversarial verifier, which assumed each finding was wrong until evidence showed otherwise. Verdicts: 36 confirmed, 15 partial, 0 refuted. The controller re-checked all five Critical findings in the code by hand.
- **Mechanical sweep.** `terraform init -backend=false && terraform validate` in all 104 Terraform example directories, with Terraform 1.17.1.

Scores below are the auditors' scores, given before verification.

## Critical findings (all verified)

1. **`examples/system-design/01-realtime-websockets.md:501` puts `app_ingress_mode` directly under `aws:`.** `envs/aws/workload/config.tf:52` only reads `aws.workload.app_ingress_mode`. The schema also accepts the top-level key, so the plan passes while the ALB silently stays internal and clients cannot connect. **Repo trap too:** `config/landing-zone.schema.json` defines an `aws.app_ingress_mode` that nothing reads, and `config/landing-zone.example.yaml:386` shows the commented key at that level. Fix 01, then remove the dead schema key and move the example comment under `workload:`.
2. **`examples/system-design/17-multi-tenant-saas.md:525` uses `ou: Prod`.** Child OUs are keyed by path (`Workloads/Prod`, `modules/aws/governance/organization/outputs.tf:16-21`), and `modules/aws/stages/organization/main.tf:35` looks up `ou_ids[each.value.ou]`, so the `aws-organization` plan fails. The same bug is in `docs/runbooks/aws-add-account.md:23`. Use `ou: Workloads/Prod` in both.
3. **Three module examples pin `?ref=v0.1.0`**, a tag that does not exist (`git ls-remote --tags origin` returns none): `modules/aws/stages/security/examples/basic`, `modules/gcp/stages/organization/examples/basic`, `modules/saas/stages/saas-workload/examples/basic`. Copying them fails at `terraform init`. This is the release-please placeholder (`CONTRIBUTING.md:293-299`). Cut v0.1.0, or switch these examples to relative sources until the first release.
4. **`examples/app-delivery/ecs-fargate-delivery.example.yml:69-72` describes the task definition by the service name.** The golden path names the service `<svc>` (`modules/aws/compute/ecs-fargate/main.tf:121`) but the family `<env>-<svc>` (`modules/aws/stages/app-services/main.tf:58`), so the deploy step fails. Read the family from the app-services outputs.
5. **`examples/vpc-sc/main.tf:36-52` puts a Workload Identity pool in the ingress rule's `sources.resource`, with `resources = null` and `ANY_IDENTITY`.** VPC-SC only accepts a project, folder, organization or VPC network there, and `ingressTo.resources` is required, so the API rejects the rule (`terraform validate` passes). Put the pool's principalSet in `identities`, set `identity_type = null`, and list the target project numbers in `resources`.

## Important findings (verified)

### System-design library

| File:line | Finding | Fix |
|---|---|---|
| 01:237 | The send path writes the idempotency record, the counter and the message in three separate writes. A crash leaves a permanent `seq` gap or a record pointing at a message that was never stored. | One `TransactWriteItems`, or teach clients that gaps can happen. |
| 03:174 | The order view drops stale events with one `aggregate_version`, but it consumes four producers whose counters do not share a sequence. | Keep one version per source. |
| 06:157 | The `postings` primary key `(entry_id, line)` cannot be created on a monthly-partitioned table (reproduced on PostgreSQL 17). | Add `created_at` to the key. |
| 06:80 | The design sends Stripe about 1,500 calls/s with 3,000 in flight. Stripe's live defaults are 100 requests/s and 50 concurrent, so the limits bind at 1×, not at 10×. | Size against the real limits and state that an increase is needed. |
| 06:158 | Balance = snapshot + postings since, bounded by `created_at`. A transaction that starts before the snapshot and commits after it is lost from every later balance. | Bound by commit order (for example a monotonic sequence assigned at commit), or snapshot with a safety lag. |
| 09:406 | The cost deep dive never prices storage. It grows by 2.4 PB a month, about $605,000 a month by month 12, the same order as the CDN bill. | Add storage cost and lifecycle levers (Glacier tiers, rendition pruning). |
| 09:187 | The GCP edge is Cloud CDN on a backend bucket. Media CDN, Google's video-streaming CDN, is never mentioned. | Name Media CDN and state the trade-off (it needs sales onboarding). |
| 11:64 | The backfill seeds its shadow table from a snapshot at "T1 minus a margin", but BigQuery time travel keeps at most 7 days. Older rebuilds must replay up to 2 years of raw. | Add periodic state checkpoints. |
| 12:488 | The GCP catalog section mixes two table types: Spark reads BigQuery-managed Iceberg through an exported metadata snapshot, not the Lakehouse REST catalog. | Separate the two paths. |
| 12:690 | The GCP curated table snippet has no day partitioning and no `require_partition_filter`, but the scan-cost arithmetic depends on both. | Add both. |
| 13:27 | The stateless gateway drops `pod` and aggregates, so several replicas write the same counter series, which Prometheus and Managed Service for Prometheus reject. The per-pod `topk` rule also becomes impossible. | Keep a replica label, or aggregate in one place. |
| 15:37 | Carts (DynamoDB) backups are copied cross-account and cross-region, which AWS Backup allows only with "advanced features for DynamoDB" turned on. | State the prerequisite. |
| 15:66 | The requirement is 35 days hot and a year cold, and the repo policy keeps 365 days today. The replacement policy snippet keeps 35 days, so copying it drops the one-year retention. | Keep the 365-day rule with a cold-storage transition. |
| 17:327 | Shuffle sharding cuts the share of other tenants that are fully affected to 1/28, not the capacity lost. A poison tenant still takes 2 of 8 workers (1/4). | Reword. |
| 17:367 | "GCP has no session tags" leaves out Cloud Storage Credential Access Boundaries (downscoped tokens), the pooled-bucket equivalent. | Add them. |
| 19:194 | Hard deletes leave no tombstone, so a late, older upsert brings a deleted document back and breaks the 1-minute revocation requirement. | Keep a tombstone version. |
| 19:178 | One `vector(1024)` column and one HNSW index are used for "write both" during a re-embed. That contradicts the file's own rule against mixing models in one index, and the replace deletes the other model's rows. | Separate column or table per model. |
| 19 (serving) | The managed open-model hosting tier is missing: SageMaker AI endpoints, Vertex AI Model Garden endpoints, Bedrock Custom Model Import. | Add it as the middle option. |

### Other examples

| File | Finding | Fix |
|---|---|---|
| `app-delivery/ecs-fargate-delivery.example.yml` | Ignores the app-services output contract (deploy role, family, container name) and never mentions `enable_external_deployments`. | Read them from the outputs. |
| `app-delivery/gke-autopilot-delivery.example.yml:19-21` | Grants project-level `roles/container.developer` (read and write on every Kubernetes object, Secrets included, in every cluster in the project). | Namespace-scoped RBAC with a minimal IAM role. |
| `app-delivery/gke-autopilot-delivery.example.yml:9-17, 54` | Gives conflicting advice: the bootstrap pool vs the app-deploy pool (`apps-<env>`). | Use the app-deploy pool. |
| `app-delivery/gke-autopilot-delivery.example.yml:52, 73` | `auth@v2` and `get-gke-credentials@v2`, tag-only, with no pin warning. v3 is current, and the repo already pins `auth` v3.0.0 by SHA. | Pin to SHAs at v3. |
| `aws-landing-zone/README.md` and tfvars | The "no default means REQUIRED" model is out of date: no `envs/aws/*` variable lacks a default. The real required inputs, `landing_zone_name` and `tfc_organization`, are not mentioned. | Rewrite around `config/landing-zone.yaml`. |
| `aws-landing-zone/aws-security.tfvars.example` | Marks four role ARNs as required that the stage creates itself. | Mark them optional. |
| `aws-landing-zone/aws-backup.tfvars.example` | Marks two roles as required that the root creates. The sample fixed-account backup role skips member-role creation, so the org policy names a role that does not exist in each member account. | Remove the sample ARN. |
| `aws-landing-zone/aws-workload.tfvars.example` | Marks `log_archive_bucket_name` (legacy; setting it skips the contract read) and `workload_account_key` as required. | Mark them optional and explain. |
| `vpc-sc/README.md` | The violation log filter would return nothing. | Filter `cloudaudit.googleapis.com%2Fpolicy` on the accessed service. |
| `modules/` | 25 of 124 modules have no example, including every application runtime and golden-path module. | Add basic examples, starting with the golden paths. |

## Scores

### System-design library

| File | Correctness | Completeness | Best practice | Teachability |
|---|---|---|---|---|
| README | 9 | 8 | 9 | 9 |
| 00 primer | 8 | 8 | 8 | 7 |
| 01 real-time WebSockets | 6 | 8 | 7 | 8 |
| 02 notifications | 9 | 9 | 8 | 8 |
| 03 microservices | 7 | 9 | 8 | 8 |
| 04 adapter gateway | 7 | 9 | 8 | 8 |
| 05 rate limiter | 8 | 9 | 8 | 9 |
| 06 payment ledger | 7 | 8 | 7 | 8 |
| 07 URL shortener | 9 | 9 | 9 | 8 |
| 08 news feed | 8 | 9 | 8 | 9 |
| 09 video | 8 | 7 | 7 | 8 |
| 10 search | 9 | 9 | 8 | 9 |
| 11 ETL | 7 | 9 | 8 | 8 |
| 12 lake and warehouse | 7 | 8 | 8 | 9 |
| 13 observability | 7 | 9 | 7 | 8 |
| 14 n-tier network | 8 | 9 | 8 | 7 |
| 15 data DR | 7 | 8 | 8 | 8 |
| 16 active-active | 8 | 9 | 8 | 8 |
| 17 multi-tenant SaaS | 7 | 9 | 8 | 8 |
| 18 job scheduler | 9 | 9 | 9 | 8 |
| 19 LLM serving and RAG | 7 | 8 | 7 | 8 |
| **Mean** | **7.7** | **8.6** | **7.9** | **8.1** |

### Other examples

| File | Correctness | Completeness | Best practice | Teachability |
|---|---|---|---|---|
| `examples/README.md` | 7 | 6 | 7 | 7 |
| `app-delivery/cloud-run` | 7 | 8 | 6 | 8 |
| `app-delivery/ecs-fargate` | 3 | 5 | 5 | 6 |
| `app-delivery/gke-autopilot` | 5 | 5 | 4 | 5 |
| `app-services/dev.app-services.tfvars` | 9 | 9 | 9 | 9 |
| `dev.tfvars.example` | 9 | 8 | 8 | 9 |
| `aws-landing-zone/README.md` | 4 | 6 | 5 | 6 |
| `aws-landing-zone/*.tfvars.example` | 4 | 5 | 4 | 6 |
| `presets/README.md` | 9 | 9 | 9 | 8 |
| `presets/*` | 9 | 8 | 9 | 8 |
| `cloud-armor` | 8 | 7 | 7 | 7 |
| `cloud-storage` | 8 | 8 | 8 | 7 |
| `kms` | 6 | 7 | 8 | 6 |
| `vpc-sc` | 4 | 7 | 5 | 6 |
| `workloads` | 5 | 6 | 6 | 4 |

Of 12 sampled module examples, 9 scored 7-9 on correctness. The two git-sourced ones scored 3 (Critical 3). `supabase/vault-secrets` lost points for literal placeholder secrets with no sensitive-variable pattern.

## Notable Minor findings

There are about 90 Minor findings. These are the most useful:

- **Primer:** the "mandatory policies" list omits 4 of the 10 policies in `policies/opa/policies.hcl`; two line references point at the wrong lines; there is no glossary for newcomers.
- **Product names:** "BigLake Iceberg tables in BigQuery" is now "Apache Iceberg managed tables" (12); Dataplex vs Knowledge Catalog naming differs across 11, 12 and the primer; "formerly Vertex AI Search" vs "being renamed" in 10.
- **Cost figures:** 05 prices Valkey at the Memcached ECPU rate ($0.0034 vs $0.0023 per million; about $360 a month, not $530). 09 omits audio transcoding and prices delivery at US rates.
- **Copyable code:** 05's Lua script needs three clamps (negative elapsed time, cost above burst, negative remaining quota). 09 references `transcode_dlq` and `aws_cloudfront_key_group.media` without declaring them. 16's conflicting writes both become version 7, so the conflict-copy key collides.
- **Partials downgraded to Minor:** egress allowlists with `.amazonaws.com` (06, 14) mirror the repo example config, and the real gap is missing endpoint policies; the 08 Memorystore ×10 plan exceeds 125 primaries with replicas, but already suggests splitting clusters; prefill compute in 19 is about 20% of an H100's FP8 peak and is worth a line.
- **Other examples:** `kms/README.md` cites a wrong module path, a wrong rotation limit and a non-existent `prevent_destroy_keys` variable; `workloads/README.md` says IAM is authoritative (it is additive); the Cloud Run workflow says no `auth` SHA is vetted, but the repo pins v3.0.0.

## Strengths worth keeping

- **Estimates drive decisions** across the library. Each block ends with the decision it drives, for example 01's NLCU-vs-LCU bill and 07's birthday bound justifying the conditional insert.
- **Honest repo grounding.** Gap notes match the code; 14 places the repo's own gaps (IAP deny, missing default route, central endpoint DNS) inside the design narrative with file:line references.
- **Interview-grade correctness patterns:** 04's four-outcome error taxonomy and "failover follows side effects"; 11's commit-position guard with `(P, -1)` snapshot stamps; 17's fail-closed row-level security; 18's lease, fencing and cron reasoning (no Important findings).
- **The presets and overlays** pass mock plans for every key and value, and the presets README warns about the `*_overrides` replace-not-merge trap.

## Recommended order of fixes

1. **The five Critical findings.** The 17 and runbook `ou` fix and the schema and example-YAML `app_ingress_mode` fix are repo changes; the rest are example edits.
2. **Library Important findings**, worst-first: 06 (three issues), 19 (three), 01, 03, 11, 13, 15 (two), 12 (two), 09 (two), 17 (two). Each walkthrough is near the 6,000-word cap, so every fix needs a matching cut.
3. **The other examples:** rewrite `aws-landing-zone` around `config/landing-zone.yaml`, update both delivery workflows to the app-services outputs and pinned v3 actions, and fix `vpc-sc`.
4. **Add examples** to the 25 modules without one, starting with the golden-path stages.

The raw auditor and verifier files are kept locally in `.superpowers/audit-2026-11-08/` (untracked).
