# Enterprise Boilerplate Audit — 2026-11-05

Scope: the whole repo at `4e05c90` (main, after PR #587). The audit covers five dimensions: SOTA best practice, boilerplate capability, maintainability, security and modularity. Five independent expert-persona reviews ran in parallel, and their headline claims were then re-verified by hand. **Legend:** ✅ = re-verified directly (code read, command run, or GitHub API). ◐ = reported with file:line evidence but not independently re-run. ❓ = needs a real cloud to confirm.

This audit deliberately does **not** take earlier audits' "resolved" markers at face value. Several do not hold.

---

## Verdict

This is a **well-engineered module library with immaculate hygiene. It is not yet a fork-and-go enterprise launch pad.** The four previous audits optimised for what static tooling can see: validation blocks, pin consistency, mock tests and docs. Each remediation round added surface, such as new modules, flags and docs, faster than it closed real-apply gaps. Three structural problems dominate:

1. **The merge gate is not real.** `main` is red on Format, TFLint and Checkov right now. Branch protection allowed the merge anyway. Every "gates green" claim since then is unverified.
2. **Identity is the soft underbelly on both clouds.** One org-level GCP security-admin SA serves *every* TFC workspace, including dev workloads and speculative PR plans. On AWS, workloads run through management-account credentials and `OrganizationAccountAccessRole`. A PR to a dev workload can yield org-admin credentials.
3. **Defaults would fail or break on first real apply, and the "hardened" path doesn't exist.**
   - The default root-level RCP denies the STS calls that TFC OIDC and AWS service roles rely on.
   - The default `gcp-workload` plan fails.
   - SaaS single-provider plans fail.
   - The production presets that earlier audits claimed as fixes were never committed.

### Scorecard (out of 10)

| Dimension | Score | One-line reason |
|---|---|---|
| SOTA best practice | **6** | AWS org-policy coverage is ahead of the curve (RCP + declarative EC2 policy + v6 region fan-out). It is let down by a single shared identity, no plan-time policy-as-code, no write-only secrets, and a VPC-SC design that can't stage changes. |
| Boilerplate capability | **3** | Foundation only. It has no app roots, configuration is scattered across 4–5 roots, the TFC/credential wiring is manual, and three verified first-apply failures exist. |
| Maintainability | **5** | Excellent tooling intent, but an unenforced gate, 25 dead modules (23%), no tags or releases, mock-only testing and documentation drift. |
| Security | **4** | Strong hygiene: SHA-pinned actions, fail-closed WIF conditions, Object Lock and a GCP org-policy baseline. The privilege model has critical escalation paths, and "containment" is cosmetic. |
| Modularity | **6** | Provider handling and variable typing are exemplary. The host god-module remains, there is no project primitive, layers cannot be mixed within a cloud, AWS tagging is effectively absent, and cross-root contracts are string-keyed. |

---

## Part 1 — Critical findings (fix before anyone forks this)

### C1. The merge gate is unenforced, and `main` is red ✅
- PR #587 merged with **Terraform Format, TFLint, Security/Checkov and Validation Summary all failing**.
- On `main`:
  - `make fmt-check` fails on `envs/gcp/workload/tests/root.tftest.hcl` and `envs/saas/tests/root.tftest.hcl`.
  - TFLint reports 109 `terraform_standard_module_structure` violations, all caused by the host "decomposition" moving outputs into `modules/gcp/stages/host/outputs-*.tf`. Because `make lint` stops at the first failing root under `set -e`, more may be hidden behind it.
  - The Security Scan workflow fails on push.
- Branch protection is `enforce_admins: false`, `required_pull_request_reviews: null`, `strict: false`. "Validation Summary", which the workflow comments call "the single required status check", is **not** in the required contexts. The 218-leg validate matrix gates nothing.
- **Local/CI tool skew** produces false greens. Checkov passes locally on 3.2.490 (0 failures) but fails in CI on the action's 3.3.17. `make security` does not pin a scanner version.
- **Fix:**
  1. Add "Validation Summary" to the required checks.
  2. Set `enforce_admins=true` and require one review.
  3. Run `terraform fmt`.
  4. Merge the split host output files back into `outputs.tf`, or scope the rule.
  5. Pin checkov/trivy/tflint versions in `.tool-versions` and in the Makefile.

### C2. One org-level security-admin SA serves every GCP workspace, in plan and apply ✅
- `envs/gcp/bootstrap/main.tf:11-14` gives WIF trust to the four control-plane workspaces **and every `gcp-workload-<env>`**.
- `modules/gcp/stages/bootstrap/main.tf:145-149` binds all of them to `module.terraform_admin_sa.email`. That SA holds org-level `iam.securityAdmin`, `orgpolicy.policyAdmin`, `accesscontextmanager.policyAdmin`, `logging.admin` and `securitycenter.admin` (`:101-105, 157-162`).
- The provider condition is only `terraform_organization_name == '<org>'` (`modules/gcp/iam/workload-identity/main.tf:175`). Bindings are keyed by workspace **name**, with no `terraform_run_phase`, project or workspace-ID pinning.
- **Attack path:**
  1. Open a PR touching `envs/gcp/workload/`.
  2. TFC runs a speculative plan with dynamic credentials. `speculative_enabled` is never disabled (`modules/tfc/workspace/main.tf`).
  3. A `data "http"` block exfiltrates `data.google_client_config.x.access_token`.
  4. That token carries org security-admin rights: grant self owner, delete org policies, empty perimeters, retarget sinks.
- A not-yet-created `gcp-workload-<env>` name can also be squatted by any TFC user who can create workspaces.
- A standing **GitHub** WIF trust to the same SA exists (`bootstrap/main.tf:108-130`), yet no workflow requests `id-token: write`. That is unused privilege. Its trust matches mutable repo names rather than `repository_id`.
- **Fix:**
  - Use per-stage **plan (read-only) and apply SAs** via `TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL` / `TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL`.
  - Bind on `terraform_workspace_id` + `terraform_project_id` + `terraform_run_phase`.
  - Give workload SAs folder- or project-scoped roles only.
  - Disable speculative plans on control-plane workspaces.
  - Remove the GitHub pool, or bind it to a read-only SA on `repository_id`.
  - This is the Cloud Foundation Fabric FAST pattern.

### C3. The "admin containment" fix (previous audit C2, marked resolved) is cosmetic ✅/◐
- It is off by default (`enable_admin_containment = false`).
- It denies only `*.delete` (`modules/gcp/stages/organization/main.tf:168-185`). `logging.sinks.update` (retarget or blank the filter), exclusions, `servicePerimeters.update` (empty the perimeter), `orgpolicy.policy.set` and `iam.denypolicies.delete` all remain open.
- It protects `logging.googleapis.com/buckets.delete`, but the audit sink writes to a **GCS** bucket (`cloud-audit-logs/main.tf:172`). The real archive is not covered at all.
- That bucket and its CMEK live in the admin project, which the same SA created (◐ likely owner). The SA can therefore delete object generations or destroy key versions.
- The deny policy is applied by the identity it is meant to contain.
- **Fix:**
  - Put logging and KMS in a project the automation SA does not own.
  - Turn on the bucket lock by default. The global `CKV2_GCP_4` skip in `.checkov.yaml` currently hides this.
  - Expand the deny list to `update`, `exclusions`, `denypolicies`, `cryptoKeyVersions.destroy` and `storage.objects.delete`.
  - Have the deny policy owned by a separate identity.

### C4. The default AWS RCP likely breaks TFC OIDC and AWS service roles org-wide ✅ (logic) / ❓ (live)
- `modules/aws/governance/organization-policy/policies/rcp-data-perimeter.json` is attached at the org root by default (`modules/aws/stages/organization/main.tf:48`). It has two problem statements.
- **`EnforceOrgIdentities`** denies `sts:*` under `StringNotEqualsIfExists aws:PrincipalOrgID` + `BoolIfExists aws:PrincipalIsAWSService false`.
  - `AssumeRoleWithWebIdentity` (TFC OIDC) and `AssumeRoleWithSAML` carry no `PrincipalOrgID`.
  - Under `IfExists`, a missing key means the deny applies.
  - Every member-account OIDC role assumption is therefore denied.
- **`ConfusedDeputyProtection`** denies `sts:*` for service principals when `aws:SourceOrgID` is absent. It has no `Null aws:SourceAccount = false` guard.
  - EC2 instance profiles, Lambda and ECS task roles are service-principal `AssumeRole` calls with no source context.
  - Those calls are denied.
- Tests only regex for the string `aws:SourceOrgID` (`tests/plan_assertions.tftest.hcl:42`).
- **Fix:**
  - Follow the AWS `data-perimeter-policy-examples` RCPs: list specific STS actions instead of `sts:*`, add the `Null aws:SourceAccount` guard, and add `dp:exclude` tag escape hatches.
  - Validate in a sandbox org before default-attaching at root.

### C5. The hardened and cost presets that earlier audits marked "fixed" were never committed ✅
- `examples/presets/README.md`, `docs/runbooks/production-hardening.md:57-99` and `envs/gcp/organization/variables.tf:235` all point to `examples/presets/*.tfvars`.
- `git ls-files examples/presets` returns only `README.md`.
- `.gitignore:7` (`*.tfvars`) swallows the files, because the exception `!examples/*.tfvars` covers only the top level.
- **Consequence:** the only documented route to a hardened posture does not exist. That posture covers enforced VPC-SC, containment, CMEK org policy, Cloud Armor/OWASP and CIS alarms. Defaults remain dry-run or off.
- **Fix:**
  1. Add `!examples/**/*.tfvars`.
  2. Write and commit the presets.
  3. Add a CI job that runs `terraform test`/`plan` against each preset.

### C6. Default first-apply failures ✅
- **`gcp-workload` default plan fails.**
  - `envs/gcp/workload/main.tf:153-168` always passes a perimeter with `access_policy_name = var.vpc_sc_access_policy_name`, which defaults to null. That trips the vpc-sc module's validation.
  - The shipped root test hides this with `override_module "host"`.
  - `network-hub` gates the same input correctly (`stages/network-hub/main.tf:69`).
- **The SaaS single-provider path fails** (◐ verified by `terraform plan` in a scratch copy). `envs/saas/providers.tf` configures both `supabase` and `vercel` unconditionally. Supabase-only fails for lack of a Vercel token, and the reverse also fails. That contradicts the matrix in `provider-selection.md`.
- **The example tfvars point at a workspace that doesn't exist.** `examples/dev.tfvars:24` sets `organization_workspace_name = "organization"`, overriding the correct default `gcp-organization`.
- **Example emails get past the placeholder guard.** `@ashes.example.com` defeats `@example\.(com|org|net)$` (`envs/aws/organization`), so placeholder addresses would create real AWS accounts with undeliverable root emails.

---

## Part 2 — Findings by dimension

### 1. SOTA best practice

| Sev | Finding | Evidence | Fix |
|---|---|---|---|
| High | **No plan-time policy-as-code.** There is no Sentinel, OPA/Conftest or Infracost, and no `check` blocks in 213 configurations. PR CI never runs `terraform plan`, so reviewers never see a plan. | grep across the repo and workflows | Add a TFC policy set (Sentinel or OPA) via `tfe_policy_set`, speculative-plan PR comments, Infracost, and `check` blocks for invariants such as "prod ⇒ VPC-SC enforced". |
| High | **Secrets land in state** despite running TF 1.14 in CI. The floor is `~> 1.9` in 224 places, which blocks `ephemeral`/`*_wo`. `known-gaps` S4 claims the floor was raised; it was not. `secret_data = var.secret_values[...]` (`gcp/data/secret-manager/main.tf:88`) and the `google_sql_user` password (`gcp/data/cloud-sql/main.tf:153`) both write secrets to state. | ◐ | Raise the floor to `>= 1.11`. Use `secret_data_wo`/`password_wo` with `*_wo_version`, `ephemeral "random_password"` and tfe `value_wo`. |
| High | **The TFC layer misses the native features.** No `trigger_patterns` are set, so a PR that touches only `modules/**` never plans or applies, leaving silent undeployed drift (✅ `envs/tfc-admin/main.tf:64`). There is no `tfe_workspace_settings`/remote-state consumers (roots use full `terraform_remote_state` rather than `tfe_outputs`), no `assessments_enabled` (native drift detection), no run triggers and no variable sets. | ✅/◐ | Set `trigger_patterns = ["<dir>/**","modules/**"]`, switch to `tfe_outputs` with explicit consumers, and add assessments and run triggers. |
| Medium | **VPC-SC is dry-run XOR enforced.** `use_explicit_dry_run_spec = var.enable_dry_run` (`gcp/network/vpc-sc/main.tf:108-110,201`), so an enforced perimeter can never stage a delta. Nothing ties prod to enforced. | ◐ | Use separate `status` and `spec` inputs, plus validation that `prod && dry_run` fails. |
| Medium | **GCP lags the enterprise blueprint.** It has no PAM entitlements, no principal access boundary, no Log Analytics log buckets and no `google_logging_organization_settings`. Standing `organizationAdmin` is granted to `user:` principals (`stages/organization/main.tf:9-13`). | ◐ | Grant to groups only, use PAM for JIT org-admin, and add a central log bucket with analytics. |
| Medium | **CI hardening gaps.** No `harden-runner`. The docs bot uses a classic `repo` PAT (`documentation.yml:30-38`) rather than a GitHub App token. The apply-metadata tag filter omits bootstrap, projects, network-hub and tfc-admin. | ◐ | — |
| Medium | **`local-exec` plus `npm ci` from the public registry at apply time** (`supabase/vault-secrets`). It runs without `--ignore-scripts`, uses `null_resource` rather than `terraform_data`, and assumes Node exists on TFC agents. | ◐ | Vendor a prebuilt bundle or use a SQL provider, and use `terraform_data`. |
| Low | `try()` wraps attributes already declared `optional()` (about 50 in `vpc-sc/main.tf`), which masks type errors. Provenance codes appear in variable descriptions despite the CLAUDE.md rule. There are no `removed {}` blocks and no OpenTofu or Stacks stance. | ◐ | — |

**At or above SOTA:**
- AWS RCP + `DECLARATIVE_POLICY_EC2` (IMDSv2, VPC/AMI/snapshot block public access, serial console), enabled by default.
- AWS provider v6 per-resource `region` fan-out for GuardDuty and delegated admin.
- WIF preconditions that refuse a null attribute condition.
- SHA-pinned actions with `permissions: {}`.
- RDS-managed master secrets.

### 2. Boilerplate capability (adopter journey)

**Realistic time to first working environment** for an experienced platform engineer, assuming no real-apply surprises:

| Persona | Promised | Realistic | Why |
|---|---|---|---|
| SaaS-only | ~30 min | 2–4 h | Provider-token trap (C6). tfc-admin creates unwanted `gcp-*` workspaces. |
| GCP-only foundation | — | 4–7 days | 4 ordered roots, hand-entered `environments` object ×4, undocumented GCP dynamic credentials (C4 below), C6 blockers. **Plus 1–2 weeks to run an app.** |
| AWS-only | — | 1.5–3 weeks | Out-of-band org creation, 6 root emails, console steps for Identity Center and StackSets, a hand-built OIDC role, runbook that contradicts code. About $1.5k/month idle before any workload. |
| Both clouds | — | 3–5 weeks | Almost no shared configuration. |

| Sev | Finding | Evidence |
|---|---|---|
| Critical | **No single source of configuration.** The full `environments` object (CIDRs, IAM) is a required input in bootstrap, organization, projects and network-hub, with "keep in sync" prose. `project_prefix` is required in 5 roots. `*.tfvars` is gitignored, so VCS-driven TFC workspaces get no values and everything is hand-entered in the UI. tfc-admin pushes one shared variable map to every workspace and cannot set per-workspace values. | ◐ `envs/gcp/*/variables.tf`, `envs/tfc-admin/main.tf:66-69` |
| Critical | **GCP TFC dynamic credentials are never wired.** `TFC_GCP_PROVIDER_AUTH` / `TFC_GCP_WORKLOAD_PROVIDER_NAME` / `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` appear nowhere in the repo. Providers only impersonate, so a remote run has no base credential. | ✅ (0 grep hits) |
| High | **The AWS credential model in the runbook contradicts the code.** `aws-bootstrap.md` says to set each workspace's run role to `account_role_arns[...]`, but the security and backup roots pin `allowed_account_ids = [management]`. No `aws_iam_openid_connect_provider` exists in `modules/aws`. The "real terraform-run role" the runbook says phase 1 created is in fact a required input that nothing creates. | ◐ |
| High | **The app "golden path" is docs-only and wouldn't run.** `deploying-a-service.md` references an undeclared SA, puts Cloud SQL on the hub VPC (where PSA is disabled), and points at a nonexistent registry. No deploy identity (app-repo OIDC) exists on either cloud. `cloud-run`, `cloud-sql`, `gke-autopilot`, `ecs-fargate` and `rds-aurora` are referenced by **no root**. The house is still empty. | ✅ (dead-module check) |
| High | **tfc-admin is incomplete.** It always creates GCP workspaces (no `enable_gcp`), configures no remote-state sharing, run triggers or variable sets, and sets no per-workspace credentials. | ◐ |
| Medium | **SCP side-effects on real use** (❓): the region SCP may deny the `enable_edge` stack (ACM/CloudFront globals not carved out), and the deny-tamper SCP blocks Terraform teardown of workload Config recorders. | ◐ |
| Medium | **Gaps against enterprise expectations.** No compliance control matrix (SOC 2 / ISO 27001 / NIST 800-53; only CIS comments). No multi-region DR. Idle AWS cost (about $1.5k) exceeds the default $1k budget. No hub-less "starter" AWS path. | ◐ |
| Medium | **Stale onboarding docs.** `add-environment.md` predates the root split. `README.md:80-86` says bootstrap, projects and network-hub are "folded into gcp-organization". The QUICK_START init sequence is wrong. | ◐ |
| Low | Hard-coded regions (`europe-west1`/`eu-west-2`/`us-central1`) in about 30 places. "Ashes" branding and `security@ashesproject.com` in templates. No rename/scaffold script. | ◐ |

### 3. Maintainability and longevity

Measured: 110 modules, 14 roots, 33k module LOC, 17k test LOC, 23.6k lines of Markdown (188 files), 410 commits (95% one author), **0 git tags**, 220 committed lockfiles.

| Sev | Finding | Evidence |
|---|---|---|
| Critical | **The merge gate is unenforced** (C1). | ✅ |
| Critical | **Nothing proves a real apply works.** Zero real-apply/terratest tests. 984 `command = plan` runs against 21 `apply` runs, all mocked. 121 `override_module` uses. Some assertions are tautological: overriding remote state to `"r-abcd"` and then asserting `== "r-abcd"` (`envs/aws/security/tests/root.tftest.hcl:60-67`), plus about 53 `x == var.y` echoes. C4 and C6 are exactly the class of bug this lets through. | ◐ |
| High | **25 of 110 modules (23%) are dead**, referenced by no root, stage or example. Most were added *as audit remediations*. Examples: `gcp/monitoring/control-plane` (the "self-observability" fix), `gcp/compute/cloud-run`, `gcp/data/cloud-sql`, `aws/compute/ecs-fargate`, `aws/data/rds-aurora`, `aws/network/load-balancer`. Each still costs a CI leg, a lockfile, Dependabot bumps and docs. | ✅ (spot-checked 3) |
| High | **The most critical code is the least tested.** `envs/gcp/organization` is the only root with no tests (✅). `modules/gcp/stages/organization` is the largest `main.tf` (407 lines) and has 1 behavioural assertion, a `length(...) > 0`. `stages/workload` and `governance/kms` have 0 plan assertions. | ✅/◐ |
| High | **No versioning or release discipline.** No tags. The tag-triggered apply workflow can therefore never fire. CHANGELOG was last touched 2026-09-09 (about 40 commits unlogged). Every module change hits all 14 roots atomically. | ✅ (tags) |
| High | **CI scaling cliff.** 218 cold-init validate legs against GitHub's 256-leg cap. The `make test` job inits more than 120 directories serially with no plugin cache. No path filtering. | ◐ |
| Medium | **Documentation sprawl and drift.** README badges say 98 modules and 203 suites; the real figures are 110 and 234. CLAUDE.md under-lists roots and layout. The Makefile ships `apply-gcp-organization` while CLAUDE.md forbids local apply. 14 of 43 docs are not linked from `INDEX.md`. Broken links. 5 audit documents in 2 months. | ◐ |
| Medium | **Copy-paste.** 687 hand-written validation blocks; the same `project_id` regex appears in 14 files. Roots re-declare their stage's variables one to one (saas 30/30, organization 24/29). 199 module-level lockfiles with drifting google versions (7.31 vs 7.39). The lockfile platform doc is self-contradictory (CLAUDE.md says `darwin_amd64`, the Makefile says `darwin_arm64`). | ◐ |
| Medium | **Scanner gaps.** No `tflint-ruleset-aws` for 49 AWS modules. tfsec is EOL, folded into Trivy, but still runs alongside Trivy and Checkov. No shellcheck. | ◐ |
| Low | Bus factor of 1: CODEOWNERS is an inert `@your-org/*` placeholder and no reviews are required. History is dominated by remediation churn. `required_version ~> 1.9` claims 1.9–1.13 support that is never tested. | ✅ (protection API) |

### 4. Security

Beyond C2–C4:

| Sev | Finding | Evidence / attack path |
|---|---|---|
| High | **AWS workloads run with management-account-rooted credentials.** `OrganizationAccountAccessRole` trusts only the management account, so a workload workspace's base identity is a management-account principal, and SCPs never restrict the management account. A PR speculative plan in `envs/aws/workload` therefore yields management credentials. The TFC OIDC trust (`sub` scoping) is hand-made and not in code. | ◐ `envs/aws/workload/providers.tf:8-20` |
| High | **The deny-tamper SCP is partly inert and full of gaps.** It protects roles that live in the management account, where SCPs don't apply. Its carve-outs key on management-account ARNs, which never match a member session. It omits `cloudtrail:PutEventSelectors`/`UpdateTrail`, `guardduty:CreateFilter` (auto-archive)/`UpdateDetector`, `config:DeleteDeliveryChannel`/`PutConfigurationRecorder`, `securityhub:BatchDisableStandards`, `access-analyzer:DeleteAnalyzer`, `ec2:DeleteFlowLogs`, `kms:ScheduleKeyDeletion`, and changes to OAAR. | ◐ `scp-deny-tamper.json` |
| High | **The log archive can be crypto-shredded.** `aws/data/kms-key` grants `kms:*` to one `key_admin_arn`, so admin and user are the same principal. The same admin covers the log-archive, forensics and security-tooling keys, and no SCP denies key deletion. Object Lock COMPLIANCE does not help if the key is destroyed. | ◐ |
| High | **Supabase vault RPCs are likely callable with the public anon key.** `bootstrap.mjs` only runs `REVOKE ... FROM PUBLIC`. Supabase's default privileges explicitly grant EXECUTE on `public` functions to `anon`/`authenticated`, and those grants survive. A `POST /rest/v1/rpc/upsert_vault_secret` with the frontend anon key could then overwrite any secret, and `delete_vault_secret` has no namespace filter. The functions are SECURITY DEFINER with `search_path = public`. | ✅ (code) / ❓ (live) |
| High | **No control-plane alerting.** `gcp/monitoring/control-plane` (marked resolved as M-obs) is instantiated nowhere. Org IAM, org-policy, VPC-SC and sink changes go unalerted. | ✅ |
| Medium | **The drift token is effectively code execution as the admin SA.** Queue Plans on `gcp-organization` combined with a shared plan/apply identity. `drift-detection.yml:57` falls back to the full `TFC_TOKEN`. | ◐ |
| Medium | **The TFC layer has no security controls.** No team access, project separation, policy sets or run tasks. tfc-admin's VCS PR plans may expose an org-level `TFE_TOKEN`. | ◐ |
| Medium | **Network gaps.** The hierarchical SSH/RDP deny is attached only to the shared folder, not the env folders. AWS VPC Block Public Access has `exclusions_allowed: enabled`, so any member admin can exempt a VPC. | ◐ |
| Low | Unsalted `sha256(postgres_url)` in state. Vercel env vars default to `sensitive = false`. The `break_glass_role_arn` regex accepts `role/*`, which would turn the carve-out into a whole-account exemption. Activating break-glass requires a pipeline apply, which is unusable when the pipeline is the incident. | ◐ |
| Suppressions | Most are justified. The real risk is hidden by the two `tfsec:ignore:google-iam-no-privileged-service-accounts` entries (`bootstrap/main.tf:146,207`, which mask C2) and the global `CKV2_GCP_4` skip (masks C3). | ◐ |

**Strengths:**
- No `pull_request_target`, and untrusted input reaches `run:` only via `env:`.
- WIF fail-closed preconditions.
- The RCP/declarative-policy *intent*.
- S3 Object Lock COMPLIANCE.
- GCP org-policy baseline: domain-restricted sharing, no SA keys, no external IPs, public access prevention, `DATA_READ`/`DATA_WRITE` audit config.

### 5. Modularity

| Sev | Finding | Evidence |
|---|---|---|
| High | **The host god-module was only split across files, not modules** (the previous H3 is "resolved" in name only). It has 74 variables, 30 module calls, 48 outputs, 16 `enable_*` toggles and 2,065 lines. It is used as both hub and spoke: `network-hub` calls `../host` twice. | ◐ |
| High | **AWS tagging is effectively absent.** Only 8 of 49 AWS modules accept `tags`, and there are **zero** `default_tags` across the repo (✅). Meanwhile `cost-governance` activates cost-allocation tags that nothing writes. GCP label keys are inconsistent (`managed_by` vs `managed-by`). The templates have no tags or labels variables. | ✅ |
| High | **The AWS VPC primitive owns no routing.** No `aws_route_table` exists in `aws/network/vpc` or `aws/stages/workload` (✅). Gateway endpoints are created with no `route_table_ids`, and the spoke VPC has no route to the TGW (❓ live). The VPC name is hard-coded as `"workload"`. | ✅ (code) |
| High | **Three different ways to create a GCP project** (raw `google_project` ×2, upstream project-factory ×1, the latter force-enabling `container.googleapis.com`). There is no `project` primitive, so baseline behaviour depends on which stage created the project. | ◐ |
| High | **Layers cannot be mixed within a cloud.** Every GCP remote-state read is unconditional. AWS workload hard-requires network and security state, and `coalesce(var.override, remote_state…)` still reads the state. That contradicts `provider-selection.md:61` ("additive"). The cross-cloud any-combination claim **is** true; the within-cloud claim is not. | ◐ |
| High | **Cross-root contracts are string-composed map keys** (`project_ids["shared-hub"]`, `"${env}-host"`). `merge()` is right-wins, so an environment named `shared` would silently replace the hub and DNS projects (❓). AWS account-key strings are hard-coded across 5 roots. | ◐ |
| Medium | **No consumable versions.** No tags and relative-path sources only, so deprecated-alias outputs can never be removed. Thin one-resource wrappers (`iam-organizations-features`, `supabase/project`, `aws/network/dns-records`). `network-firewall` is one rule per call (called 9× in host). Mismatched cross-cloud interfaces and conflicting default regions in primitives. The SaaS topology is hard-coded to qa/uat/production. | ◐ |
| Low | Convention violations: bare `enable`, negative `disabled`, `create_` used as an infix, and `delete_protection`/`deletion_protection`/`enable_deletion_protection` for the same concept. One `list(any)`. Cross-cloud references are scalar-only (`tostring`). | ◐ |

**Strengths:**
- No provider blocks in child modules, `required_providers` and `required_version` everywhere, and correct `configuration_aliases`.
- 1,436 variables, all typed and described, with exactly one `any`.
- Clean domain separation: no gcp↔aws imports.
- Values are passed in rather than discovered (12 data sources total).
- The cross-cloud any-combination claim holds.

---

## Part 3 — Remediation roadmap (ordered by leverage)

**Phase 0: stop the bleeding (≤ 1 day).**
1. Enforce branch protection: "Validation Summary" required, `enforce_admins`, 1 review, real CODEOWNERS teams.
2. Fix fmt and TFLint on `main`.
3. Pin scanner versions locally to match CI.
4. Commit the presets (`.gitignore` exception) or delete every document that references them.
5. Fix the `gcp-workload` VPC-SC gate, the example workspace name and the email guard.

**Phase 1: identity rebuild (1–2 weeks). This is the single biggest risk reduction.**
1. **GCP:** per-stage plan/apply SAs, WIF bound on workspace ID + project + run phase, workload SAs scoped to their folder, speculative plans disabled on the control plane, GitHub pool removed.
2. **AWS:** an `account-baseline` module that creates a TFC OIDC provider and plan/apply roles *in each member account*, so that management credentials are used only by `aws-organization`. SCP-protect those roles and OAAR.
3. Wire `TFC_GCP_*` / `TFC_AWS_*` per workspace from tfc-admin.

**Phase 2: make the guardrails real (1 week).**
1. Rewrite the RCP to the AWS sample patterns and validate it in a sandbox org.
2. Close the gaps in the deny-tamper SCP.
3. Split the KMS admin and user roles.
4. Make GCP containment real (update actions, GCS bucket lock, a logging project outside the SA's ownership) and on by default.
5. Wire `control-plane` alerting.
6. Fix the Supabase RPC grants.
7. Make VPC-SC status and spec independent.

**Phase 3: make it a boilerplate (2–4 weeks).**
1. One `config/<org>.yaml` read by every root via `yamldecode`, plus tfc-admin per-workspace variables and `trigger_patterns`.
2. Ship `envs/gcp/app` and `envs/aws/app` roots, each driven by a `services` map, with an app-repo OIDC deploy identity. Wire in the dead compute and data modules, or delete them.
3. Split the SaaS root per provider.
4. Add `default_tags` and labels everywhere.
5. Add a hub-less starter profile and a compliance control matrix.

**Phase 4: longevity (ongoing).**
1. A nightly ephemeral sandbox apply/destroy for 3–4 representative roots.
2. Semver release tags (release-please) and CHANGELOG enforcement.
3. A TFC policy set, Infracost, and `check` blocks.
4. A TF floor of `>= 1.11` with write-only secrets.
5. A shared plugin cache in CI with an affected-roots filter.
6. Decompose `host` into real modules with `moved {}` blocks; add a GCP `project` primitive.
7. Generated counts and a link checker for docs.
8. **Stop writing audit documents and start writing apply tests.**

---

## Remediation status (Phase 0, 2026-11-05)

| Item | Status |
|---|---|
| fmt drift on `main` | Fixed (`terraform fmt`). |
| TFLint `terraform_standard_module_structure` (109) | Fixed: host `outputs-*.tf` / `variables-*.tf` merged back into `outputs.tf` / `variables.tf`. TFLint is clean across every root. |
| Checkov failing in CI (3.3.17) | Fixed: justified skips for `CKV2_GCP_13` (cloud-sql `log_duration`), `CKV2_AWS_27` / `CKV2_AWS_8` (rds-aurora). The CI version passes, 0 failures. |
| Local/CI scanner skew | Fixed: `.tool-versions` pins checkov 3.3.17. `make security` runs that exact version via `uvx` and refuses to run on a mismatch. |
| C5: presets never committed | Fixed: `.gitignore` exception added. Seven presets written (the six documented, plus `prod-gcp-workload`). `check-consistency.sh` (CI) now fails on unknown preset keys and on docs that reference missing presets. |
| C6: `gcp-workload` default plan fails on VPC-SC | Fixed: the perimeter is gated on `vpc_sc_access_policy_name`. The new `envs/gcp/workload/tests/default_plan.tftest.hcl` runs the **real** host stage, with no override. |
| **New, found by that test:** the flow-logs export in the default workload plan fails validation (empty `destination`) | Fixed: the host stage derives the BigQuery sink destination when it creates the dataset. |
| **New, found by that test:** enabling VPC-SC on the workload fails (`null` method_selectors passed to `for_each`; `try()` does not catch null) | Fixed: 11 null-safe `coalesce(try(x, null), [])` calls in `vpc-sc/main.tf`. |
| C6: example workspace name / email guard | Fixed: `gcp-organization` in the examples. The guard now matches `[@.]example.(com\|org\|net)`, also covers `workload_accounts`, and has tests. |
| C1: branch protection (`enforce_admins`, required review, "Validation Summary" required) | **Operator action**: a repository settings change, not made from code. |
| Pre-existing tfsec findings (gke-autopilot ×4, cloud-sql ×2) | Not addressed. tfsec is not a CI gate; Trivy is. |

The two "new" bugs show why Part 3, Phase 4 matters: a single test that skips the module override found three default-path plan failures that 234 mocked suites had missed.

## Bottom line

The repo's own previous audits called it "an immaculately governed empty house". That is still true, and today's audit adds that **some of the locks on the house are painted on**.
- The gate that guards `main` can be bypassed.
- The automation identity that every workspace shares can rewrite the org.
- The default AWS data perimeter would probably lock out the pipeline itself.
- The "hardened" configuration exists only as a README.

None of this is hard to fix, and the underlying module craftsmanship is genuinely high. The next investment should be identity and a real-apply test loop, not more modules or more documentation.
