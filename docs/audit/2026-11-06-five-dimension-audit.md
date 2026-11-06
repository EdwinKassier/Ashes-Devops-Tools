# Five-dimension enterprise boilerplate audit (2026-11-06, HEAD 44eb490)

## How this audit was done

- Five independent expert reviews ran in parallel: security, boilerplate capability, maintainability, SOTA practice and modularity. Each reviewer was told not to trust earlier `docs/audit/*` reports and to verify against the code.
- The most severe findings were then re-checked by hand. This document only marks a finding **VERIFIED** if it was read in code or reproduced.
- What was run:
  - local gates: fmt, docs, count, links, consistency;
  - `terraform test` in 4 modules and roots;
  - `validate` on 3 roots;
  - the scaffolder, run into a scratch copy, then mock plans of 5 roots from its output;
  - the GitHub WIF regex bypass, reproduced against the shipped pattern.

## Verdict

This is a **well-engineered, security-conscious module library that has never been proven as a running platform.**

- **What's good:** the primitives, AWS guardrails and test discipline are above what most enterprise forks start from.
- **What's missing:**
  - no stage or root has ever been applied to a real cloud;
  - the management-account and detective-control guardrails have exploitable holes;
  - the day-2 operating model (adding a service, team or environment) has no committed home;
  - the GCP network design is a generation behind;
  - one person holds all the context, and nothing is versioned.

A new business could not stand this up without a senior platform engineer for about a week on GCP, and 2–3 weeks on AWS.

| Dimension | Score | One-line reason |
|---|---|---|
| SOTA best practice | **7.0** | AWS guardrails are current (RCPs, declarative EC2, centralized root, provider-v6 region fan-out, `*_wo`). GCP networking is 2021-era: tag-based VPC firewalls and peering instead of NCC. Policy-as-code never sees a real plan. |
| Boilerplate capability | **6.0** | One YAML drives four providers, and 4 of the 5 scaffolded roots plan. But the documented GCP quick-start fails its first plan. Day-2 changes need 2–7 applies, the golden path piles every service into the network host project, and identity needs raw IDs. |
| Maintainability | **5.0** | Gates are real, fast and green. But there have been zero real applies, bus factor is 1, there are 0 tags, each setting is copied by hand through about 5 places, and 62% of commits are audit churn. |
| Security | **6.2** | Member-account design is strong (self-propagating boundary, RCP tenant pin, SHA-pinned CI). But the management account has no SCP backstop, and its `aws-security` role can blind org detection. The detective denylists are incomplete, the WIF pin can be bypassed, and production checks only warn. |
| Modularity | **6.5** | Primitives are disciplined: no `any`, no child providers, correct `configuration_aliases`. But gcp-workload is a stage hiding in a root, networks are single-region in both clouds, the tfc-admin catalog is hand-coded, and contracts are untyped. |
| **Overall** | **6.1** | |

---

## Part 1 — Critical

### C1. Nothing above the primitive level has ever been applied for real (VERIFIED)

- **Sandbox E2E:** 32 runs, all skipped `pull_request` runs. The suites cover only kms, bucket, vpc, subnet, secret-manager, log-archive-bucket and kms-key (`tests/e2e/{gcp,aws}/main.tf`). They cover no stage and no root.
- **Drift detection:** every run shows green, but each one skipped with "Skipping scheduled drift detection cleanly".
- **Backends:** until PR #591, every root's backend was invalid (`backend "cloud"`), so no root could even `init`.
- **Admitted gaps:** `docs/known-gaps.md` has 9–10 "mock-tested only / validate on a real org" entries. They sit on load-bearing paths: the per-stage GCP SA role matrix, the CloudTrail KMS condition, contract overrides and scoped access policies.
- **Consequence:** the first forker becomes the integration tester for IAM matrices, WIF principalSets, org-trail delivery and apply ordering. Mock tests (41% of runs are `expect_failures`) can't catch API rejections.
- **Fix:**
  1. Run a nightly real apply and teardown into sandbox orgs: tfc-admin → gcp-bootstrap → gcp-organization → gcp-projects → gcp-network-hub → gcp-workload-dev, and aws-organization → … → aws-workload-dev.
  2. Add a "last successful real apply < 7 days" gate.
  3. Make drift and E2E fail, not skip, when they are not configured.

### C2. Bus factor is 1, and code-owner review is not enforced (VERIFIED)

- 122 of 122 commits in the last 3 months are by one author.
- `.github/CODEOWNERS:1` is `* @your-org/platform-team`, a placeholder.
- The OPA policy set is off by default (`enable_policy_sets = false`).
- **Consequence:** a single maintainer merge reaches every apply role in both clouds (see the security Highs), with no second human.
- **Fix:**
  - real CODEOWNERS teams with at least 2 humans, with required code-owner review;
  - `enable_policy_sets = true` in the production profile;
  - ADRs for the ~10 load-bearing decisions, instead of audit narratives.

---

## Part 2 — High

### Security

**S-H1. The `aws-security` management-account role can blind org-wide detection (VERIFIED).**

- **Evidence:**
  - `modules/aws/iam/tfc-management-roles/main.tf:144-151` grants `organizations:DisableAWSServiceAccess` for `cloudtrail`, `guardduty`, `config`, `securityhub` and `securitylake`.
  - `:155-169` grants `DeregisterDelegatedAdministrator`.
  - `:256` deliberately leaves `cloudtrail:PutEventSelectors` allowed and relies on a CIS alarm, which the same pipeline can manage.
- **Why it matters:** SCPs don't apply in the management account, so these grants have no backstop.
- **Exploit:** one apply of `aws-security` can do any of these:
  - narrow the event selectors to nothing, so the trail still says "logging" but records nothing;
  - disable trusted access for CloudTrail, which detaches every member account from the org trail;
  - deregister the GuardDuty or Security Hub delegated admin.
- **Fix:**
  - Remove the `Disable*` and `Deregister*` actions from the apply role, and keep them behind break-glass.
  - Deny `PutEventSelectors`, `PutInsightSelectors`, `RemoveTags` and `PutResourcePolicy` on the trail after creation, through a separate create-time role or a `aws:CalledVia` / tag condition.
  - Deny alarm and metric-filter deletion for the CIS alarms.

**S-H2. GitHub WIF tenant pin can be bypassed (VERIFIED, known since the last audit and still open).**

- **Evidence:** `modules/gcp/stages/organization/main.tf:416-428`.
- **Exploit:** this condition passes the regex: `assertion.repository_owner_id == '123' && (assertion.ref == '((' ) || true || (')' == ')')`.
  - CEL evaluates it as `(…) || true`, so tokens from any GitHub repo are accepted.
  - `wl-<env>-apply` holds `workloadIdentityPoolAdmin` and `serviceAccountAdmin` on its folder. That turns the bypass into a durable external backdoor.
- **Fix:** stop regex-validating free-form CEL. Generate the condition from structured inputs (owner ID, repo IDs, refs, environments), and compare the custom constraint against that exact canonical string.

**S-H3. KMS owner-tag planting (VERIFIED, known and still open).**

- **Evidence:**
  - `tfc-management-roles/main.tf:215` grants `kms:TagResource` on `*`, gated only by `aws:RequestTag`.
  - `OwnedKeysOnly` then grants `kms:*` on any key that carries that tag.
- **Exploit:** tag any management-account CMK whose key policy delegates to IAM, then decrypt with it.
- **Fix:** grant `TagResource` only in the same statement as `kms:CreateKey`. Otherwise also require `aws:ResourceTag/owner` to already equal the role's tag.

**S-H4. A member-account `tfc-apply` can blind Config and flow logs, and break log-archive delivery (VERIFIED).**

- **SCP:** `scp-deny-tamper.json.tftpl` (~L38-58) exempts `privileged_arns`, which includes `tfc-apply`, for:
  - `config:PutConfigurationRecorder`;
  - `ec2:DeleteFlowLogs`;
  - `s3:PutBucketPolicy` on log-archive.
- **Permissions boundary:** `DenyDisablingDetectiveControls` (`tfc-oidc-baseline/main.tf` ~L150) does not cover Config, flow logs or `logs:DeleteLogGroup`.
- **Exploits:**
  - A compromised dev workload apply can empty the account's Config recording group and delete its flow logs. That account then goes dark for detection and forensics.
  - The log-archive apply can rewrite the bucket policy to deny `cloudtrail.amazonaws.com`. Org trail delivery then stops silently; Object Lock doesn't prevent this.
- **Fix:**
  - Add those actions to the boundary.
  - Make log-archive `PutBucketPolicy` break-glass only.

### Boilerplate

**B-H1. The documented GCP quick-start fails at its first plan (VERIFIED).**

- **Evidence:**
  - The scaffolded `prod` environment has `is_production: true`.
  - That trips the precondition at `modules/gcp/stages/bootstrap/service_accounts.tf:329-337`: production workspaces must be WIF-bound by ID.
  - The step that writes those IDs (`terraform -chdir=envs/tfc-admin output -raw gcp_bootstrap_tfvars > …/tfc-workspaces.auto.tfvars`) is only in `docs/runbooks/bootstrap.md`. `QUICK_START.md` omits it.
- **Fix (either):**
  - add the step to QUICK_START;
  - better, have gcp-bootstrap read the IDs through `tfe_outputs` when `tfc_organization` is set.
- **Also:** default `phase0_admin_impersonation_expires_at` to now + 7 days.

**B-H2. The app golden path deploys every team's services into the Shared VPC host project (VERIFIED).**

- **Evidence:** `envs/gcp/workload/main.tf:443` sets `project_id = local.env_config.host_project_id`.
- **Consequence:** network admins and every app team share one project. That means no per-team IAM, quota or billing isolation, the opposite of the Google blueprint and FAST.
- **Fix:** add a `service_team` key on each `app_services` entry. Target the project-factory project by default; use the host project only as an explicit opt-in.

**B-H3. Day-2 changes have no committed home (VERIFIED).**

- **The gap:** `app_services` and `service_teams` can't be expressed in `config/landing-zone.yaml`. `gcp.workload` only takes `bootstrap_image`, `public_ingress` and `presets_by_environment` (`envs/gcp/workload/config.tf:72-111`).
- **The docs disagree on where they go:**
  - `promotion.md:22,40` says `examples/<env>.tfvars`. Only `dev.tfvars` exists, and VCS-driven runs never read it.
  - `service-team-onboarding.md:98` says to run a local `terraform apply -target`, which CLAUDE.md forbids.
  - `deploying-a-service.md` says workspace variables.
- **The real path:** edit `config/tfc-workspaces.yaml`, re-apply tfc-admin, then queue the workload run. That's 2 applies per service.
- **Fix:** add per-environment `gcp.workload.services`, `gcp.workload.service_teams` and `aws.workload.services` to the config schema, then rewrite those three docs around it.

**B-H4. Adding one environment takes 7 ordered applies (VERIFIED).**

- **Evidence:** `bootstrap.md:240`: tfc-admin → bootstrap → organization → projects → network-hub → tfc-admin → workload.
- **Comparison:** FAST and LZA do this as one YAML change through one pipeline.
- **Fix:** chain the applies with TFC run triggers, which are already derivable from the remote-state edges. Or collapse the per-environment SA, folder and project work into one stage.

**B-H5. Identity is bring-your-own, wired with raw IDs (VERIFIED).**

- **AWS:** `envs/aws/identity` assignments need an identity-store group ID and a 12-digit account ID. The default is `{}`, so nobody has access after stand-up.
- **GCP:** five or more Cloud Identity groups must already exist. `iam/identity-group` is example-only.
- **Fix:**
  - resolve `account_key` and the group `display_name` through `data.aws_identitystore_group` and the org contract;
  - ship default permission sets: platform-admin, read-only, network-admin, security-audit, and developer with a boundary;
  - add `enable_identity_groups` on GCP.

### SOTA

**T-H1. AWS Config only records in Security Tooling and workload accounts (VERIFIED).**

- **Evidence:** `config-org` is called only from `stages/security/main.tf:235` and `stages/workload/main.tf:203`. The "out-of-band StackSet" the comments mention doesn't exist.
- **Consequence:** management, log-archive, network, shared-services, backup and forensics accounts have no recorder. The Config-backed Security Hub controls are blind in exactly the most privileged accounts.
- **Fix:** a service-managed StackSet with `auto_deployment`, targeting all OUs.

**T-H2. GCP firewalling uses legacy VPC rules on network tags (VERIFIED).**

- **Evidence:**
  - `network-firewall/main.tf` uses `google_compute_firewall`.
  - The tiered-vpc baseline (`main.tf:140-197`) gates the database tier on `source_tags`.
  - There are zero `google_compute_network_firewall_policy` resources anywhere in the repo.
- **Consequence:** anyone with `compute.instances.setTags` can add the `compute` tag to a VM and reach the database tier.
- **Fix:** global network firewall policies with IAM-governed Secure Tags (`purpose = GCE_FIREWALL`).

**T-H3. The GCP hub/spoke uses VPC peering instead of NCC (VERIFIED).**

- **Evidence:** `stages/net-spoke/main.tf:133` creates the spoke link with VPC peering. There are zero `google_network_connectivity_hub` resources.
- **Consequence:** peering doesn't route transitively and has quota limits, so spoke-to-spoke and hybrid traffic need workarounds.
- **Fix:** an `ncc-hub` primitive using `preset_topology`, with VPC and hybrid spokes.

**T-H4. Policy-as-code never runs against a real plan (VERIFIED).**

- **Evidence:**
  - CI runs `opa test` on hand-written fixtures only (`terraform-plan.yml:547-551`).
  - The HCP policy set is off by default.
  - There are 14 policies.
- **Fix:** in CI, run `plan -out` → `show -json` → `conftest` on the example roots. Turn the policy set on in the production profile.

### Maintainability

**M-H1. Modules can't be pinned, and the release pipeline has never produced a release (VERIFIED).**

- **Evidence:**
  - There are 0 git tags.
  - All 3 `release.yml` runs failed: `RELEASE_PLEASE_TOKEN` is not set.
  - The whole repo is a single `"."` release-please package.
- **Fix:**
  1. Set the token and cut v0.1.0.
  2. Either document "fork at a tag", or move to per-domain release-please components for the roughly 20 reusable primitives.

**M-H2. The config file has no schema, so typos are silently ignored (VERIFIED).**

- **Evidence:** about 300 `try(...)` reads across the 14 `config.tf` files. Unknown keys are never rejected.
- **Consequence:** a misspelled hardening flag quietly falls back to its insecure default.
- **Fix:** a JSON Schema for `landing-zone.yaml` with `check-jsonschema` in CI and in `make init`, plus `setsubtract(keys(...), known)` checks in each root.

**M-H3. Each setting is copied by hand through about 5 places (VERIFIED).**

- **Evidence:** roots re-declare most of their stage's variables:
  - gcp-organization: 53 of 63;
  - aws-security: 38 of 48.
- **Example:** `log_archive_bucket_name` appears in the stage variable, the root variable, its validation, `config.tf` (twice), `main.tf` and the example YAML.
- **Symptom:** `scripts/check-consistency.sh` exists only to keep those copies in sync.
- **Fix:** pass typed object variables straight from the config to the stage, for example `security = local.lz.aws.security`.

**M-H4. Provider freshness has stalled, and lockfiles diverge (VERIFIED).**

- **Root lockfiles:** all 14 are at google 7.31 / aws 6.54, from May.
- **Module and example lockfiles:** already at 7.46 / 6.72. So tests exercise newer providers than the roots deploy.
- **Volume:** 240 committed lockfiles, 118 of them single-platform.
- **Dependabot:** every Terraform PR was closed.
- **Fix:**
  - commit lockfiles only for `envs/**`, `tests/e2e` and the templates;
  - point Dependabot at those roughly 17 directories;
  - add a CI check that fails when a root's lock falls behind.

**M-H5. Cross-root contract tests partly assert their own fixtures (VERIFIED).**

- **Evidence:** in `envs/aws/workload/tests/root.tftest.hcl:58-74`, 4 of 7 asserts compare the `override_data` value with itself.
- **The real gap:** nothing checks that producer outputs match the output names consumers read.
- **Fix:** a script that compares each consumer's `terraform_remote_state.*.outputs.<key>` references with the producer's `outputs.tf`. Delete the self-asserting tests.

### Modularity

**D-H1. `envs/gcp/workload` is a composition stage living in a root (VERIFIED).**

- **Evidence:** 1,530 lines composing net-spoke, billing, workload, backup, os-config, secret-manager, app-services, app-ingress and the VPC-SC perimeter (`main.tf:180-535`).
- **Asymmetry:** AWS puts the equivalent in `modules/aws/stages/workload`.
- **Naming clash:** `stages/workload` means "service-project factory" on GCP and "account baseline + spoke" on AWS.
- **Fix:**
  - extract `modules/gcp/stages/environment`;
  - rename the GCP `stages/workload` to `stages/service-project`.

**D-H2. Network hubs are single-region in both clouds (VERIFIED).**

- **GCP:** `tiered-vpc` and `net-hub` take a scalar `region`, even though GCP VPCs are global.
- **AWS:**
  - the hub VPCs and the TGW use a scalar `aws_region`, and the cross-root contract is a single `tgw_id`;
  - IPAM, by contrast, is multi-region;
  - workspace names have no region dimension.
- **Consequence:** adding a second region means forking roots.
- **Fix:**
  - GCP: `regions = map(object(...))`.
  - AWS: `tgw_ids` keyed by region, with the hub fanned out using provider v6 per-resource `region`, the same pattern the security layer already uses.

**D-H3. The tfc-admin workspace catalog and DAG are hand-coded (VERIFIED).**

- **Evidence:**
  - `envs/tfc-admin/main.tf:29-51` lists every root literally.
  - `:89-95` hand-writes the run-trigger edges, duplicating the `terraform_remote_state` edges in each root.
  - The security alias list is repeated in 3 places.
- **Doc gap:** `adding-a-cloud.md` never mentions tfc-admin, so following it produces an orphan workspace.
- **Fix:**
  - move the catalog (dir, cloud, upstreams, aliases) into `config/tfc-workspaces.yaml`;
  - derive the run triggers from it;
  - add a check that the remote-state reads match those triggers.

---

## Part 3 — Medium

| ID | Finding | Evidence | Fix |
|---|---|---|---|
| S-M1 | GCP production safety checks only **warn** | `check "production_requires_admin_containment"` (`stages/organization/main.tf:193`) and `check "phase0_impersonation_is_time_boxed"` (`stages/bootstrap/main.tf:76`). `enable_admin_containment` and `enable_audit_bucket_lock` default off | Convert both to `lifecycle.precondition`, as `production_workspaces_bound_by_id` already is |
| S-M2 | GCP containment deny has gaps even when on | No deny on `logging.sinks.create` (org-aggregated sink → exfiltration) or on org `setIamPolicy`. In "separate" mode the deny is only output, never enforced | Deny `sinks.create` except break-glass. Add a PAB or deny on org setIamPolicy for the org apply SA |
| S-M3 | Supabase DB master password is a root output and is kept in state | `envs/saas/outputs.tf:27-31` | Drop the output. Use write-only/ephemeral when the provider supports it, and rotate after create |
| S-M4 | Plan-role data-read deny is a denylist with holes (SUSPECTED) | `tfc-oidc-baseline/main.tf` ~L330-360: `apigateway:GET` API keys, `ssm:GetCommandInvocation`, `ec2:GetLaunchTemplateData` (user data), `logs:GetLogRecord`… are still readable. Non-prod PRs get speculative plans | Base the role on `ViewOnlyAccess` plus an explicit refresh allowlist |
| S-M5 | Egress inspection is log-only by default | `stages/network-hub/variables.tf:156-166`: `aws:alert_established`, empty allowlist | Fail the plan when production workloads exist and the firewall is in alert-only mode |
| T-M1 | All SCPs attach at Root. Suspended, PolicyStaging and Sandbox OUs have no policies | `stages/organization/main.tf:43-57` | Attach deny-all to Suspended. Stage policy changes through PolicyStaging first |
| T-M2 | IPAM mode is inconsistent | `aws/network/vpc/main.tf:85-87` passes no CIDR but carves subnets from `var.cidr_block`. Hub VPCs bypass IPAM | Pre-allocate with `aws_vpc_ipam_pool_cidr_allocation` and derive subnets from it |
| T-M3 | Identity Center is thin | No customer-managed policy or boundary attachments. ABAC off. No temporary elevated access on AWS, although GCP has PAM | Add CMP and boundary attachments, role-based permission sets, ABAC on by default |
| T-M4 | TFC apply role defaults to AdministratorAccess | `tfc-oidc-baseline/variables.tf:130-133` | Per-layer least-privilege apply policies |
| T-M5 | GCP folders are flat, one per environment | `iam/organization/main.tf:41-44` | A function-first tree (Common / Networking / Security / Teams) with environment subfolders |
| T-M6 | Consumers read the producer's whole state | 15 `terraform_remote_state` reads in gcp-workload, 12 in aws-workload | `data "tfe_outputs"` (outputs only); evaluate HCP Stacks for the fan-out |
| T-M7 | Access Analyzer is home-region only, with no internal-access analyzer | `access-analyzer-org/main.tf:14-31` | `for_each` over regions; add `ORGANIZATION_INTERNAL_ACCESS` |
| B-M1 | Stale or contradictory docs | `GOOGLE_PROJECT_ID` (nothing reads it). `promotion.md:43` says tfsec, which has been removed. QUICK_START points at deprecated `stages/host` for VPN. README claims VPN/Interconnect that no root wires. `examples/dev.tfvars` has the wrong SA email and a placeholder org | Doc sweep, plus a test that every command in QUICK_START runs |
| B-M2 | Scaffolder leaves silent gaps | Never sets `org.tfc.vcs_repo` (so workspaces are CLI-driven) or `org.profile` (defaults to production, ~$1.4–1.9k/month idle). Never flags missing SaaS IDs | `--vcs-repo`, `--profile` flags; flag every required-but-empty key |
| B-M3 | Workspace names are hard-coded in `backend.tf` | Two landing zones can't share one TFC org | Tag-based selection with a prefix |
| B-M4 | Hard lock-in to Terraform Cloud | No GCS/S3 state path | Document or support a self-managed backend profile |
| B-M5 | Brownfield adoption is AWS-only | No GCP import blocks or adoption runbook | Add a GCP adoption runbook with `import` blocks for folders and projects |
| D-M1 | Contracts take 5 shapes and are typed only on the override path | `organization_contract` differs across 6 consumers. No `contract_version` | Per-layer `contracts/` modules that coerce both paths, plus a version output |
| D-M2 | Closed extension points in app-services | Cloud Run only, with no `runtime` discriminator. The stage creates its own WIF pool instead of using `iam/workload-identity` | `runtime = optional(string, "cloud-run")` with per-runtime submodules |
| D-M3 | Hidden naming coupling | `envs/aws/workload/kms.tf:97` pattern-matches the `-exec` role naming in app-services. The root inlines `aws_kms_key` instead of the kms-key module | Move the key into the stage; output the role ARN pattern |
| D-M4 | Dead and duplicate modules | `stages/host` (deprecated, 74 variables, no removal date), `gcp/network/dns-records` (duplicates `dns`), 6 unreferenced modules, 12 example-only | Delete `host` and `dns-records` in v0.2.0. Move unwired modules to `experimental/` |
| D-M5 | Possible saas ↔ workload state cycle (SUSPECTED) | saas can read any workspace through `cross_cloud_references`, while the workloads bridge saas secrets | A cycle check in tfc-admin |
| M-M1 | Audit-driven churn | 62 of 100 recent commits are audit or remediation work. 6 audit reports in 2 months. `known-gaps.md` has 45 items | Stop auditing and start operating: fix C1 first |

## Part 4 — Low

- **Workflows and TFC settings:**
  - `aws-network` and `aws-shared-services` still allow speculative PR plans (`envs/tfc-admin/variables.tf:145-148`).
  - TFC → AWS trust is keyed on workspace name, not ID.
  - The sandbox E2E reruns on every push once a PR is labelled; it needs required reviewers on its environment.
  - `documentation.yml` persists a classic `repo` PAT while running repo scripts.
- **Defaults and inputs:**
  - The region-restriction SCP exempts the run role.
  - `arn:aws:` is hard-coded in permission-set defaults.
  - Declarative EC2 has no Allowed-AMIs setting.
  - The external-boundary mode leaves `baseline_protected_arns` pointing at the internal policy.
- **GCP feature gaps:**
  - SCC uses v1 notifications only; no posture or mute rules.
  - No KMS Autokey.
  - The default audit sink goes to GCS rather than Log Analytics.
- **Code and docs:**
  - `modules/vercel/project/main.tf:144` uses the deprecated `serverless_function_region`.
  - Variable naming is inconsistent: `deletion_protection` vs `enable_deletion_protection`, `region` vs `aws_region`, and `kms_key_arn` / `_id` / `_name`.
  - CLAUDE.md lists the vercel/null provider constraints wrongly.
  - The `drift-detection.yml` header contradicts its body.

---

## Genuine strengths (keep these)

- **AWS guardrails:**
  - an RCP data perimeter with confused-deputy protection;
  - declarative EC2: IMDSv2, VPC BPA, snapshot block;
  - centralized root access with an `aws:AssumedRoot`-aware SCP;
  - a `check` that flags weakened core guardrails;
  - a self-propagating permissions boundary.
- **Detection:** delegated admins for all security services, with region fan-out using provider v6 `region`.
- **GCP governance:** managed org-policy constraints with a legacy→managed map, IAM deny, PAB, PAM and per-stage least-privilege SAs.
- **Terraform discipline:**
  - write-only `*_wo` arguments for secrets;
  - `import`, `moved` and `removed` blocks;
  - no `any` types and no child-module providers;
  - correct `configuration_aliases`;
  - 293 test suites;
  - every Action SHA-pinned;
  - no `pull_request_target`.
- **Operating model:**
  - cloud selection by workspace rather than conditional providers, which is correct;
  - one config file driving every root;
  - contract overrides that let any downstream root run without its upstream workspace;
  - honest known-gaps and control-matrix docs.
- **Unique value against FAST and LZA:** one config across GCP, AWS, Supabase and Vercel, and a codified TFC layer.

## Prioritised remediation (highest leverage first)

1. **Prove it runs (C1).** One nightly real apply per cloud, through the workload-dev root. Expect it to surface 10+ real defects. Fix those before anything else on this list.
2. **Close the management-account and detective holes (S-H1, S-H3, S-H4, S-M1).** Remove the disable and deregister grants, lock the trail selectors and the log-archive bucket policy, extend the boundary, and make the production checks hard preconditions.
3. **Fix S-H2 structurally.** Generate the WIF condition; stop pattern-matching CEL.
4. **Day-2 operating model (B-H1, B-H2, B-H3, B-H4, M-H2).** A schema'd config with services, teams and identity; service projects by default; chained run triggers; a corrected QUICK_START.
5. **Second human and versioning (C2, M-H1).** Real CODEOWNERS, OPA policy sets on, v0.1.0 tag.
6. **Modernise GCP networking (T-H2, T-H3, D-H2).** Network firewall policies with Secure Tags, NCC, and region-keyed hubs in both clouds.
7. **Structural refactors (D-H1, D-H3, M-H3, D-M1).** The GCP environment stage, a generated workspace catalog, object pass-through from config to stage, and typed versioned contracts.
8. **Coverage (T-H1, T-M7).** Config recorders and Access Analyzer in every account and region.

Steps 1–4 would plausibly lift the overall score from about 6.1 to 7.5. Without step 1, every other fix stays mock-verified, which is what each of the last five audit rounds found.
