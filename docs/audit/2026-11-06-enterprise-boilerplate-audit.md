# Enterprise Boilerplate Audit — 2026-11-06

**Scope.** The whole repo at `92ea58b` (main, after PR #590).

**Method.** Five independent expert-persona reviews ran in parallel:
- principal cloud architect (SOTA practice),
- platform-consultancy lead (boilerplate capability),
- staff IaC maintainer (maintainability),
- cloud red-teamer (security),
- Terraform module designer (modularity).

Their headline claims were then re-checked by hand.

**Legend.**
- ✅ re-verified directly: code read, command run, or GitHub API queried.
- ◐ reported with file:line evidence but not independently re-run.
- ❓ needs a real cloud to confirm.

Earlier audits' "resolved" markers were **not** taken on trust. Three of them do not hold.

**Status.** Most findings are remediated on branch `claude/enterprise-boilerplate-audit-81fe4f` ([PR #591](https://github.com/EdwinKassier/Ashes-Devops-Tools/pull/591)). See [Part 6](#part-6--remediation-status) for what is fixed, what an independent re-score found, and what is still open.

---

## Verdict

This is still a **high-quality module library that nobody can actually deploy.** Five audit rounds have optimised what mock tests and linters can see. This round found a day-one blocker that all of them missed. It hides behind the same blind spot: nothing in CI, drift detection or E2E has ever touched a real backend or cloud.

1. **No root can `terraform init`.** All 14 `envs/**/backend.tf` declare `backend "cloud" {}`. That is not a valid backend type. HCP Terraform needs a top-level `cloud {}` block. CI only runs `init -backend=false`, so this has been latent since 2025-12.
2. **The merge gate is not the documented gate.** Live branch protection requires a context that never reports (`Terraform Tests`). It does not require `Validation Summary`, and `enforce_admins=false`. Every merge is an admin bypass.
3. **The most privileged credential is still exposed to PR plans.** The hand-created `tfc-admin` workspace holds an org-admin `TFE_TOKEN`. It is only codified (and so only gets `speculative_enabled=false`) when `manage_tfc_admin_workspace=true`, and that defaults to `false`. SaaS workspaces always run speculative plans with account-wide Supabase/Vercel tokens.
4. **Hardening is opt-in, persistence is open.** The following hardening controls all default off:
   - GCP admin containment
   - OPA policy sets
   - VPC-SC enforcement

   Apply identities on both clouds can also mint external OIDC/WIF trusts. No boundary, SCP, org policy or OPA rule prevents this.

### Scorecard (out of 10)

| Dimension | 11-05 → wave 4 | **Now** | One-line reason |
|---|---|---|---|
| SOTA best practice | 6 → 8 | **7** | Modern primitives are present: RCPs, declarative EC2, write-only args, managed constraints, phase-pinned dynamic credentials. But the root-deny SCP breaks `AssumeRoot`, policy-as-code is off and never runs against a plan, GCP deny guardrails are applied with gcloud, VPC-SC uses a narrow service list, and the network uses peering rather than NCC. |
| Boilerplate capability | 3 → 6.5 | **4** | The design is right (one config file, generated workspaces, golden paths). But `terraform init` fails on every root, and there are 28–32 manual steps per cloud. The shipped config also fails the gcp-bootstrap and organization checks. |
| Maintainability | 5 → 8 | **6** | Local gates are genuinely green and well designed. But branch protection doesn't match the docs, there are zero tags or releases, drift and E2E have never run (yet show green), bus factor is 1, and churn is audit-driven. |
| Security | 4 → 7 | **6** | The identity design is above average: per-stage SAs, exact-`sub` OIDC, and a self-propagating boundary. Against that: the TFC layer leaks to PR plans, OIDC/WIF backdoors are possible, `tfc-apply` is exempt from audit-tamper SCPs, containment is off by default, and one management role is shared by three roots. |
| Modularity | 6 → 8.5 | **6.5** | Primitives are excellent: no `any`, no child providers, a Fabric-grade project module. But stage baselines are hardcoded with no override, roots duplicate stage interfaces, the same contract has three shapes, cross-cloud names don't match, and nothing can be pinned by tag. |

The previous re-scores were inflated, because they measured what had been *added* rather than what *works*. The drop in Boilerplate and Maintainability is driven by findings that are verifiable today, not by a harsher rubric.

---

## Part 1 — Critical (fix before anyone forks this)

### C1. Every root's backend is an invalid type, so `terraform init` fails ✅

**Evidence.**
- All 14 `envs/**/backend.tf:2` contain `backend "cloud" {`. I reproduced it on Terraform 1.14.3:
  ```text
  $ terraform init -backend-config=organization=acme
  Error: Unsupported backend type … There is no explicit backend type named "cloud".
  To configure HCP Terraform, declare a 'cloud' block instead.
  ```
- Four roots also use `workspaces { prefix = … }` (`envs/gcp/workload`, `envs/saas`, `envs/aws/workload`, …). `cloud {}` does not support `prefix`. It supports `name` or `tags` only.

**Why it was missed.** `terraform-plan.yml:218` and `Makefile:54` only ever run `init -backend=false`.

**Blast radius.** All of these fail on day one:
- tfc-admin first apply
- gcp-bootstrap phase-0 local apply (QUICK_START steps 1–4)
- aws-organization option-A local run
- every `make plan-*`

TFC VCS-driven runs *may* work, because TFC overrides the backend. That is unverified ❓.

**Fix.**
1. Replace each block with `terraform { cloud { workspaces { name = "…" } } }`, plus `TF_CLOUD_ORGANIZATION`.
2. For the multi-workspace roots, use `workspaces { tags = ["gcp-workload"] }` and select the workspace with `TF_WORKSPACE`.
3. Add a CI job that runs a real `terraform init` (no `-backend=false`) against a throwaway HCP org, or at minimum `terraform init` with a `TF_CLOUD_ORGANIZATION` that is expected to fail only on auth.

### C2. Branch protection is not the documented gate, and every merge is an admin bypass ✅

**Live state** (`gh api …/branches/main/protection`):
- contexts = `Discover Terraform Roots, Terraform Format, Terraform Docs Check, TFLint, Meta Lint, Terraform Tests, Security / Checkov, Security / Trivy`
- `strict=false`
- `enforce_admins=false`

**What's wrong.**
- `Terraform Tests` never reports, because the jobs are named `Terraform Tests (shard N)`. No PR can merge without bypass.
- `Validation Summary` is not required. CLAUDE.md and `docs/guides/BRANCH_PROTECTION.md:11,70` say it is "the single required check".
- So validate (10 shards), ShellCheck, OPA and CODEOWNERS gate nothing.
- `scripts/check-required-checks.sh` validates the *doc*, not the live API, so it passes.
- CODEOWNERS is still `* @your-org/platform-team`.

**Fix.**
1. Apply the documented protection: `Validation Summary` only, `strict=true`, `enforce_admins=true`, one review, code-owner reviews.
2. Make the check script diff against live protection when `GH_TOKEN` is present.
3. Name real owners.

### C3. `tfc-admin` speculative plans expose an org-admin TFE token ✅

**Evidence.**
- `envs/tfc-admin/variables.tf:145-149` lists `tfc-admin` in `speculative_disabled_workspaces`.
- But the workspace is only managed when `manage_tfc_admin_workspace` is true, which defaults to `false` (`:82-85`). The hand-created workspace keeps TFC's default (speculative on).
- README:44 and `docs/runbooks/bootstrap.md:194` claim speculative plans are off.

**Attack.**
1. Open a PR under `envs/tfc-admin` that adds a `data "external"` block printing `$TFE_TOKEN`.
2. The speculative plan exfiltrates a token that can manage teams, variables and policy sets.
3. With that token the attacker controls every cloud apply identity.

**Fix.**
1. Default `manage_tfc_admin_workspace = true`.
2. Fail the plan if the workspace is unmanaged.
3. Run tfc-admin CLI-driven with no VCS PR trigger.

### C4. Nothing has ever been applied for real, yet the dashboards are green ✅

**Evidence.**
- `sandbox-e2e.yml`: 6 runs ever, all `skipped`.
- Drift Detection reports **success in about 10s daily**. Its log says `TFC_TOKEN … not configured. Skipping …` and then prints "All workspace plans completed — no drift detected."
- C1 is the proof of what mock-only coverage hides.

**Fix.**
1. Make skipped drift and E2E runs report *neutral/failed*, never "no drift".
2. Fund one sandbox org per cloud.
3. Make E2E a required, scheduled check.

---

## Part 2 — High

### Security

**S1. AWS apply identities can mint persistent external web-identity backdoors.** ✅
- The boundary denies OIDC-provider changes only on the baseline ARNs (`modules/aws/iam/tfc-oidc-baseline/main.tf:270-287`).
- `iam:CreateOpenIDConnectProvider` is denied nowhere in the repo.
- `DenyPrivilegedRoleTampering` (`:183-200`) applies only to the privileged role ARNs.
- The RCP deliberately omits `AssumeRoleWithWebIdentity`.
- **Attack:** a workload apply creates a role with the boundary plus admin rights. The role trusts `app.terraform.io` with `sub=organization:attacker-org:*`, or a new GitHub OIDC provider. The result is MFA-less admin access that survives credential rotation.
- **Fix:** add an SCP and boundary deny on `CreateOpenIDConnectProvider`, `CreateSAMLProvider` and `UpdateAssumeRolePolicy` (break-glass exempt). Add an OPA rule requiring an org-pinned `sub` on federated trusts.

**S2. GCP workload apply SAs can create external WIF trust and own their folder.** ◐
- The default `workload_folder_roles.apply` includes `projectIamAdmin`, `serviceAccountAdmin` and `workloadIdentityPoolAdmin` (`modules/gcp/stages/bootstrap/variables.tf:224-247`).
- There is no `iam.workloadIdentityPoolProviders` or `iam.workloadIdentityPoolAwsAccounts` org policy.
- Legacy `iam.allowedPolicyMemberDomains` doesn't restrict `principalSet://` members.
- **Fix:**
  1. Add an allow-listed `iam.workloadIdentityPoolProviders`.
  2. Move to `iam.managed.allowedPolicyMembers`.
  3. Replace folder-level `projectIamAdmin` with conditional per-project grants.

**S3. Any account's `tfc-apply` can blind detective controls.** ◐
- The `DenyWeakenSecurityServices` and Object-Lock tamper SCPs exempt `privileged_arns` (`scp-deny-tamper.json.tftpl:37-60, 85-101`). These include *every* account's `tfc-apply` and `OrganizationAccountAccessRole`.
- The boundary's `DenyDisablingDetectiveControls` misses these actions:
  - `config:PutConfigurationRecorder`
  - `ec2:DeleteFlowLogs`
  - `guardduty:UpdateDetector`
  - `guardduty:CreateFilter`
  - `cloudtrail:PutEventSelectors`
  - `cloudtrail:UpdateTrail`
- **Fix:** scope the exemption with `aws:PrincipalAccount` = security-tooling. Add the missing actions.

**S4. The GCP audit trail is erasable by the `gcp-organization` apply SA.** ✅ (default) / ◐ (bypass)
- `enable_admin_containment` defaults to `false` (`modules/gcp/stages/organization/variables.tf:412-416`). The previous audit's "on by default" fix does not hold.
- Even with containment on, `tagUser` can unbind the keyring's protection tag. Only an alert covers that, and key-version destroy then crypto-shreds the audit bucket.
- **Fix:**
  1. Containment on for any production environment, as a precondition rather than a warning.
  2. Put the audit keys and buckets in a logging project the apply SA has no roles on.

**S5. SaaS workspaces always run speculative PR plans with static account-wide tokens.** ✅
- `production_workloads` covers only `gcp-workload-*` and `aws-workload-*` (`envs/tfc-admin/config.tf:91-94`).
- **Attack:** a PR plan exfiltrates `SUPABASE_ACCESS_TOKEN`. That gives management-API access to every project in the account, including SQL execution.
- **Fix:**
  1. Add `saas-*` to the speculative-disabled set.
  2. Use per-environment scoped tokens.

**S6. One management-account admin role serves three roots.** ✅
- `aws_management_workspaces = ["aws-organization","aws-security","aws-backup"]` (`envs/tfc-admin/main.tf:170`).
- The 11-05 goal of "management creds only for aws-organization" is not met.
- **Fix:** give each root its own management role, least-privilege per root.

**S7. Repo-level GitHub secrets are reachable from any branch.** ◐
- `TFC_TOKEN_DRIFT`, `RELEASE_PLEASE_TOKEN` and `DOCS_BOT_PAT` are not environment-scoped.
- A write-access user can push a workflow that dumps them. `TFC_TOKEN_DRIFT` can queue API speculative runs on control-plane workspaces.
- **Fix:**
  1. Move these secrets to environments restricted to `main`.
  2. Replace the PATs with a GitHub App.

**S8. The GitLab WIF trust is a prefix match.** ✅
- `modules/gcp/iam/workload-identity/main.tf:96` uses `namespace_path.startsWith('${var.gitlab_namespace}')`.
- So `acme` also matches `acme-evil` and `acmecorp`.
- **Fix:** use `== 'X' || startsWith('X/')`, or pin `project_id`.

### SOTA / correctness

**A1. The root-deny SCP blocks centralized root sessions.** ✅
- `scp-baseline.json.tftpl:5-18` denies `arn:aws:iam::*:root` with no `aws:AssumedRoot` carve-out, while `RootSessions` is enabled. `AssumedRoot` appears nowhere in the repo.
- Effect: the AWS-recommended `sts:AssumeRoot` remediation path is denied by your own guardrail ❓.
- **Fix:** add `"BoolIfExists": {"aws:AssumedRoot": "false"}` and a test.

**A2. Plan-time policy-as-code is off by default and never runs against a plan.** ✅
- `enable_policy_sets = false` (`envs/tfc-admin/variables.tf:413-417`).
- CI runs `opa test` on fixtures only.
- The policy set is sourced from the same `main` branch, so one PR can weaken a policy and land the change the policy blocked.
- **Coverage gaps:** IAM trust policies, OIDC/WIF providers, org-level role grants, sink and org-policy deletion, and KMS key policies are all uncovered.
- The admin-wildcard rule excludes AdministratorAccess and is bypassed by `NotAction`.
- **Fix:**
  1. Run `conftest` over `terraform show -json` in CI.
  2. Source the policies from a protected repo or branch.
  3. Add rules for S1–S4.

**A3. GCP deny-policy guardrails are applied by hand with gcloud by default.** ◐
- `guardrail_owner_mode = "separate"` sends JSON out for gcloud (`modules/gcp/stages/organization/main.tf:545`).
- The migration runbook uses `terraform state rm`, which contradicts the no-local-ops rule.
- **Fix:**
  1. Add a `gcp-guardrails` root and workspace that runs as its own SA.
  2. Use `removed { lifecycle { destroy = false } }` instead of `state rm`.

**A4. GuardDuty Runtime Monitoring is enabled without agent management.** ◐
- `guardduty-org/main.tf:52-75` has no `ECS_FARGATE_AGENT_MANAGEMENT`, `EKS_…` or `EC2_…` configuration.
- You pay for Runtime Monitoring but get no Fargate telemetry, and Fargate is your runtime.

### Boilerplate

**B1. The shipped config fails gcp-bootstrap.** ◐
- `prod` has `is_production: true`.
- That trips the `tfc_workspace_ids` precondition at `modules/gcp/stages/bootstrap/service_accounts.tf:334`.
- The runbook calls the step "optional" (`bootstrap.md:287`).

**B2. Required Cloud Identity groups are never created and not listed as prerequisites.** ◐
- `organization_admin_groups`, `billing_admin_groups` and `gcp-developers@` are bound but never created.
- They are missing from the `bootstrap.md:27-33` prerequisites.
- The first org apply fails with "group does not exist".

**B3. `make ci` on a fresh clone can fill the disk.** ◐
- The Makefile does not set `TF_PLUGIN_CACHE_DIR`.
- 104 directories pin `hashicorp/aws` at about 726 MB each.

**B4. There is no brownfield or Control Tower adoption path.** ◐
- `modules/aws/governance/organization/main.tf:12` always creates the organization.
- Most enterprises already have one, so first apply fails with `AlreadyInOrganization`.
- **Fix:** provide an `import {}` path and a Control Tower coexistence runbook.

**B5. GCP org-root checks fail on the shipped prod environment.** ◐
- `production_requires_admin_containment` and `control_plane_alerts_have_a_destination` fire.
- No `alert_notification_emails` key exists in the config schema.

### Maintainability

**M1. No release has ever been cut.** ✅
- 0 tags locally and on the remote.
- `release.yml` fails: `RELEASE_PLEASE_TOKEN` is unset.
- CHANGELOG still claims `[0.1.0] - 2026-11-05`, and the host README promises removal "in v1.0.0".
- Consumers cannot pin `?ref=`.
- **Fix:**
  1. Set the token.
  2. Tag `v0.1.0`.
  3. Add a CI check that every CHANGELOG version has a tag.

**M2. The tested provider and the deployed provider differ.** ◐
- 238 lockfiles pin google at three versions (7.31.0 / 7.39.0 / 7.46.2) and aws at two.
- 214 of those lockfiles are in library modules, where consumers ignore them.
- 118 lack multi-platform hashes, and that check never fails.
- **Fix:**
  1. Gitignore `modules/**/.terraform.lock.hcl`.
  2. Lock `envs/` for 3 platforms.
  3. Make the check fatal.

**M3. Bus factor is 1.** ✅
- 430 of 455 commits are from one author. CODEOWNERS is a placeholder.

### Modularity

**D1. The GCP org-policy baseline is hardcoded with no override.** ✅
- About 15 constraints are inline at `modules/gcp/stages/organization/main.tf:374-497`.
- The only inputs are additive `custom_org_constraints` and `enforce_os_login`.
- **Fix:** an `org_policy_overrides` map merged over the defaults, or a YAML factory as in Fabric.

**D2. The AWS stage drops the policy override that its module supports.** ✅
- `organization-policy` has a `policies` input.
- `modules/aws/stages/organization/main.tf:65-80` never passes it through.
- The module also replaces the whole set rather than merging.

**D3. Roots mirror their stages almost one-to-one.** ◐
- Shared variables: 49/56 (gcp-organization), 36/45 (aws-security), 30/33 (saas).
- That is about 160 duplicated declarations. Each new input means editing the stage, the root and `config.tf`.
- **Fix:** pass grouped objects through the stage, or collapse the stage into the root.

---

## Part 3 — Medium

**SOTA**
- **AWS policy coverage gaps.**
  - The declarative EC2 policy is attached only to the Workloads OU (`modules/aws/stages/organization/main.tf:49`), with no Allowed-AMIs settings.
  - The RCP covers only the 2024 launch services. It is missing ECR, Logs and DynamoDB, and has no network-perimeter statement.
  - There is no AI-services opt-out policy, and the policy-type enum rejects newer types.
- **GCP network design.**
  - VPC-SC restricts 4 services on the hub and 8 on workloads, with no `vpc_accessible_services`.
  - The PSC endpoint targets `all-apis` even with VPC-SC on, instead of `vpc-sc`.
  - There is no org-policy `dry_run_spec`.
  - Hub-and-spoke uses VPC peering rather than NCC.
  - SCC uses v1 notification configs, with no Cloud Asset feeds.
- **Cross-root plumbing is pre-2025.** It relies on `terraform_remote_state` (13) rather than `tfe_outputs` (2), with no run triggers, run tasks, Stacks or private registry.
- **AWS human access is standing AdministratorAccess.** That is the default permission set, with no JIT/TEAM option. GCP has PAM.
- **The GCP TFC WIF issuer is hardcoded** to `app.terraform.io` (`workload-identity/main.tf:219`), so HCP EU and TFE are unsupported.

**Security**
- **VPC-SC is not an effective control by default.**
  - Perimeters default to dry-run.
  - The prod check is a non-blocking `check`.
  - Workload apply SAs hold `policyEditor` on their own scoped access policy, so the pipeline that owns the data owns its perimeter.
- **Non-prod speculative plans can read secrets and state.** They see the common variable set and full upstream state.
- **Prod workload applies need one person.** The platform team has `write` on them.
- **There is a standing human path to org `securityAdmin`.** `enable_phase0_admin_impersonation=true` stays on forever.
- **App-team GitHub deploy roles trust `environment:<env>` only.** There is no `ref` pin, and environment branch policies are not codified.
- **Supabase DB password and `service_role_key` are in state and root outputs.**

**Boilerplate**
- **The SaaS path is barely config-driven.** Six required variables live only in TFC, and there is no SaaS runbook.
- **App onboarding means editing complex HCL maps in the platform workspace.** All of an environment's services share one state.
- **Costly defaults, with no `profile: starter` key.**
  - AWS Network Firewall and Security Lake are both on.
  - That is about $1.4–1.9k/month idle, above the $1k default budget.
- **The GCP location policy passes bare regions** rather than `in:<region>-locations` ❓.
- **Capability gaps:**
  - no messaging, cache, EKS, Lambda/Functions or NoSQL modules
  - no per-service alerts or SLOs in GCP app-services
  - no cross-region DR for Cloud SQL or Aurora
- **Stale runbook verification steps.** Organization outputs moved to the projects and network-hub roots.

**Maintainability**
- **Audit churn.**
  - 40 of 65 commits since September are audit, remediation or wave commits (+66k lines).
  - There are 76 provenance codes in `.tf` comments, against the CLAUDE.md rule.
  - docs/ has grown to 48 files and 9.3k lines.
- **Toggle explosion.** 218 `enable_*` declarations (136 unique), with `enable_deletion_protection` declared 11 times.
- **Mock tests largely echo their inputs.** There are 140 `override_module` uses, and only 32 runs use `command = apply`.
- **Main goes red after green PRs.** Checkov runs with a different scope on push than on PR.
- **Docs drift.** CLAUDE.md omits the `app-services` stages, `.tool-versions` uses pre-reorg paths, and C2 and M1 are drift too.

**Modularity**
- **Contract design.**
  - `organization_contract` has three different shapes across consumers.
  - Cross-root keys are string-built (`"${env}-host"`).
  - SaaS has no contract override.
- **Cross-cloud naming doesn't line up.**
  - `stages/workload` means a service-project factory on GCP but the spoke plus baseline on AWS.
  - The app-services schemas are asymmetric (`image`/`env_vars` vs `container_image`/`environment`; `repository_id` vs `repository`).
- **Roots can't use the network you bring.** Neither workload root accepts an existing VPC.
- **Plan churn from positional values.**
  - Subnet CIDRs derive from list position (`tiered-vpc/main.tf:29-31`).
  - ALB rule priorities derive from sort order (`app-services/main.tf:49,60`).
  - GCP VPN tunnels are indexed with `count`.
- **Duplication.**
  - The 94-line VPC-SC type is copied 3 times.
  - The deprecated `host` module (2.2k LOC) is the sole caller of four primitives.
  - 18 of 119 modules (15%) are never planned by a root.
- **Tagging.** 36 of 51 AWS modules have no `tags` input, and 36 of 61 GCP modules have no `labels` input.

---

## Part 4 — Genuine strengths (verified)

- **Identity design.**
  - GCP has per-stage plan/apply SAs bound to `workspace_id_phase`, with a metadata-only plan role.
  - AWS has an exact-`sub` OIDC trust per workspace and phase, a data-read deny on the plan role, and a self-protecting, propagating boundary.
- **The AWS org-policy set covers all five types.** RCP data perimeter, declarative EC2 (IMDSv2, VPC BPA, snapshot/AMI BPA), two-tier tamper SCPs, and centralized root.
- **Secrets never enter state, with one exception.** They use write-only `*_wo` arguments throughout (Supabase is the exception). Object Lock COMPLIANCE is set on the log archive.
- **Supply chain and CI hygiene.**
  - Every action is SHA-pinned, `pull_request_target` is never used, and default `permissions: {}` is set.
  - `Validation Summary` treats "skipped" as a failure.
- **Interface discipline.** No `any`, no child-module providers, 892 validation blocks, 810 `optional()` uses, and 88 `moved` blocks covering refactors.
- **One-file config.** `config/landing-zone.yaml` feeds every root and tfc-admin. The init script works non-interactively.
- **Local gates genuinely pass today:** fmt, count, links, docs, tflint (235 roots, 0 issues) and consistency. The 279 test suites are all present.

---

## Part 5 — Remediation order

**Wave A — make it deployable and make the gate real (days):**
1. C1: switch to `cloud {}` blocks and add a real-init CI job.
2. C2: fix branch protection, `enforce_admins`, CODEOWNERS.
3. C3: default `manage_tfc_admin_workspace=true`, then S5 (SaaS speculative off).
4. C4: drift and E2E must not report green when skipped.
5. M1: tag `v0.1.0`.

**Wave B — close the persistence and tamper paths (1–2 weeks):**
1. S1/S2: deny new OIDC/WIF providers outside break-glass.
2. S3: scope the tamper-SCP exemption to the security account, and complete the boundary actions.
3. S4: containment as a prod precondition, and a separate logging project.
4. S6: one management role per root.
5. S7: environment-scoped secrets.
6. S8: fix the GitLab prefix match.
7. A1: `AssumedRoot` carve-out.

**Wave C — first-run success (1–2 weeks):**
1. B1/B2/B5: config schema keys for groups, alert emails and workspace IDs, plus prereq docs.
2. B3: plugin cache in the Makefile.
3. A `profile: starter|production` key.
4. B4: a brownfield import path.
5. A SaaS runbook.
6. **Then actually run sandbox E2E.** It is the only thing that will surface the next tier of first-apply failures.

**Wave D — structural (ongoing):**
1. A2: conftest on plan JSON, policies in a protected source.
2. D1/D2: override maps for the baselines.
3. Contract types, one shape per producer.
4. M2: lockfiles only in `envs/`.
5. Delete `host` after the tag.
6. Retire toggles into profiles.
7. Freeze new audits until Wave A–C land and E2E is green.

**A process note.** Do not run a sixth audit until E2E has applied something real. Every round so far has scored the repo on artefacts that a mock cannot falsify.

---

## Part 6 — Remediation status

The fixes are on PR #591. Each was tested locally before commit, and the CHANGELOG's
`[Unreleased]` section lists them in detail. After Waves A–D, three fresh independent reviewers
re-scored the branch without trusting the CHANGELOG. Their findings were then fixed too, including
one critical regression in the remediation itself.

### Fixed

| Finding | How |
|---|---|
| C1 `terraform init` fails | Top-level `cloud {}` blocks. `make backend-check` (CI) runs a real credential-less init of every root and template. |
| C3 / S5 PR plans see privileged tokens | `tfc-admin` self-managed by default. `disable_speculative_on_saas`. |
| C4 skipped checks show green | Unconfigured drift detection / E2E fail unless `REAL_CLOUD_CHECKS_OPT_OUT=true`. |
| S1 AWS federation backdoors | RCP tenant pins (TFC org, GitHub owners or owner IDs). RCP denies built-in IdPs. SCP and boundary deny IdP create/update outside break-glass / StackSet execution. OPA `aws_iam_federated_trust_pinned`. |
| S2 GCP federation backdoors | `iam.workloadIdentityPoolProviders` / `workloadIdentityPoolAwsAccounts` allow-lists plus the custom constraint `custom.wifProviderTenantPinned`. |
| S3 detection blinding | `DenyCentralDetectionOutsideSecurityAccounts` (pipeline included), with the suppression actions added. |
| S4 GCP audit trail | Containment on by default for production, with a break-glass group from config. A plan without it fails closed. |
| S6 shared management role | `tfc-management-roles`: per-workspace least-privilege roles. The re-score found the first version escalatable. It is now limited to the trail delivery role, and break-glass and the member pivot are denied. |
| S7 repo-level secrets | Workflows run in GitHub environments, and the runbook covers branch policies. |
| S8 GitLab prefix match | Exact namespace or sub-group. |
| A1 AssumeRoot blocked | `BoolIfExists aws:AssumedRoot=false`. |
| A2 policy-as-code gaps | 10 mandatory + 4 advisory OPA policies covering trusts, basic roles and NotAction. It is still opt-in on paid tiers. |
| A4 GuardDuty runtime | Agent management for Fargate / EKS / EC2. |
| B1–B5 first-run failures | Workspace-ID handoff, group prerequisites, plugin cache, brownfield import + Control Tower runbook, alert/break-glass config keys. |
| B (re-score) Security Lake default fails | Metastore role created in code. |
| B (re-score) phase-0 artefacts manual | `templates/aws/bootstrap/*.yaml` (cfn-lint clean). |
| M1 tags / M2 lockfiles | Deployable-root lockfiles must be multi-platform (fatal). A tag still needs the operator. |
| D1 / D2 baselines not overridable | `org_policy_overrides` on GCP, and `policy_overrides` / `disabled_policies` (guarded) on AWS. |
| SOTA mediums | Root EC2 declarative baseline, AI-services opt-out, ECR/Logs in the RCP, PSC `vpc-sc` bundle under an enforced perimeter, region value groups, parameterised TFC issuer, run-trigger DAG, `starter` profile, config-driven SaaS stacks. |

### Still open (needs an operator, a real cloud, or a larger refactor)

- **Operator, GitHub-side:**
  - Apply the documented branch protection: `make required-checks-live` still fails.
  - Set `RELEASE_PLEASE_TOKEN` and cut `v0.1.0`.
  - Name real CODEOWNERS teams.
  - Configure drift detection / E2E, or opt out.
- **Real-cloud validation:** nothing has been applied for real. The least-privilege management roles, the RCP/SCP condition keys, the brownfield imports and the CloudFormation templates are the likeliest first-apply failures ❓.
- **Modularity:**
  - Roots still re-declare most stage inputs.
  - Cross-root contracts differ per consumer.
  - AWS↔GCP naming is asymmetric.
  - The deprecated `host` module is still present.
  - Many modules lack a `tags` / `labels` input.
- **Capability:** EKS / Lambda / Functions, cache, NoSQL, cross-region DR, and compliance evidence export.

### Indicative scores

The mid-remediation re-score gave SOTA 7, Boilerplate 6.5, Maintainability 7, Security 5.5 and
Modularity 6.5. Security was held down by the escalation in the new management role, which is now
fixed, together with the federation-completeness and default-breaks-apply findings. No re-score has
been run since. A real sandbox apply is the step that would let any of these scores be stated with
confidence.
