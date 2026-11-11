# Expert audit: system design, security, Terraform and delivery (2026-11-11, HEAD 5bbec399)

## How this audit was done

Four independent reviewers each took one dimension: security and identity, system design, Terraform craft, and CI/CD delivery. Each read the code, not earlier audits. Items already tracked in [`docs/known-gaps.md`](../known-gaps.md) were excluded, unless the stated severity was wrong. The lead reviewer then re-read the code for every Critical finding and a sample of High findings.

- **VERIFIED** means the code path was read end to end.
- **SUSPECTED** means the code was read, but the cloud or HCP behaviour was not tested live.
- No `apply` ran, and no cloud was touched. Local Terraform is 1.14.3, so `terraform test` could not run (the repo requires >= 1.17).

## Verdict

The repository has gone past the "module library" stage. It now has strong guardrails and very good hygiene. But three defects block production use:

1. **The TFC (HCP Terraform) trust model treats a plan as safe, and it is not.** Any platform-team member can run a CLI speculative plan on `tfc-admin`. That plan can read `TFE_TOKEN`, an org-admin token. With it, the member can apply `gcp-guardrails`, `gcp-bootstrap` and `aws-organization` alone. This was found independently by two reviewers.
2. **The default GCP hub-and-spoke network fails at the second environment.** Every environment creates a peering with the same name on the hub VPC.
3. **The GCP and AWS IP plans collide by default.** Enabling the hybrid VPN, which already ships, would produce overlapping routes.

All three have a small fix. None of them would show up in mock tests. That is the pattern behind this whole audit: 336 test suites prove that each module is correct alone. Nothing proves that the estate works as a system, with more than one environment and against the real HCP permission model.

| Dimension | Score | Previous (2026-11-06) | One-line reason |
|---|---|---|---|
| Security | **6.5** | 6.2 | AWS guardrails are above SRA baseline, but the TFC plan path and the open VPC-SC storage egress negate them. |
| System design | **6.3** | 6.5 (modularity) | Control-plane split follows the Google foundations model, but the default multi-environment network is broken and app changes are coupled to platform state. |
| Terraform craft | **7.4** | 5.0 (maintainability) | Leaf modules, typing and version hygiene are excellent. Stages are deep, large and tested mostly through `override_module`. |
| Delivery / DevOps | **6.0** | n/a | GitHub Actions supply chain is very strong. TFC permissions, prod four-eyes review and plan-time code execution are not controlled. |
| **Overall** | **6.5** | 6.1 | |

---

## Remediation status

| Finding | Status | Change |
|---|---|---|
| C1 | Fixed | The platform team gets `runs = read` on the `platform` (tfc-admin) and `saas` projects. The approvers team confirms `saas-*` runs. `saas_outputs_reader_team_ids` gives one reader team per `saas-<name>` workspace (the shared `saas_outputs_reader_team_id` fails the plan). `scripts/check-consistency.sh` rejects `external`/`http` data sources, provisioners and their providers outside an allowlist. |
| C2 | Fixed | `gcp-network-hub` creates `hub-to-<env>` for each peering-mode environment whose spoke network exists (it lists them with `google_compute_networks`). `gcp-workload-<env>` creates only the spoke side; its `hub_peering_state` output shows `INACTIVE` until the hub side exists. `gcp-projects` grants the network-hub SAs `roles/compute.viewer` on each environment folder. |
| C3 | Fixed | `aws-network` reads `aws.network.{top_cidr,regional_cidrs,inspection_cidr,egress_cidr}` from config, with defaults in `10.64.0.0/10`. The aws-workload `vpc_cidr` default moves to `10.72.0.0/16`. tfc-admin fails its plan on any GCP/AWS overlap in the config file. Example, sandbox and scaffold configs follow the plan. |

| H1 | Fixed | No default VPC-SC rules in the environment perimeter; validations reject a pool as an ingress source and `ANY_IDENTITY` egress to `*`. |
| H2 | Fixed | The tenant-pin constraint denies a pinned-issuer provider with an uploaded JWKS. |
| H3 | Fixed (delegated path) | IAM-controlling workload roles are not delegable; gcp-organization grants them; gcp-projects no longer does. Data-plane admin roles stay delegable (known-gaps). |
| H4 | Fixed | Production workloads get custom access (variables read-only); the approvers team confirms applies. |
| H5 | Design only | [ADR 0015](../adr/0015-team-owned-app-stacks.md), Proposed. |
| H6 | Partly fixed | Trigger patterns scoped to each root's modules, checked by CI. The shared config file still triggers every workspace. |
| H7 | Fixed (opt-in preview) | `network/secure-web-proxy`, hub `secure_web_proxy`, spoke `egress_proxy`, workload `enable_egress_proxy`. |
| H8 | Fixed | The hub perimeter holds only the hub and DNS projects. |
| H9 | Fixed | `npm ci` runs in the same command as each script. |
| H10 | Fixed | No `ignore_changes`; dashboard JSON is normalised. |
| H11 | Partly fixed | Real wiring suites for `aws/stages/security` and the gcp-organization CMEK path; no stage e2e. |
| M1, M2, M3, M4, M5 | Fixed | Plan-role deny extended (managed policy); log-archive SCP covers all bucket configuration; forensics role uses principal keys; companion access-log bucket; StackSet policy tamper deny. |
| M6, M7, M8 | Fixed | Refresh-only drift against the applied configuration; `pg` pinned and updated by Dependabot; exact Terraform version in TFC. |
| M9, M12 | Fixed | Production Cloud SQL regional by default; production app services need a service team. |
| M10 | Fixed | `state-backup.yml` and [runbook](../runbooks/state-backup.md). |
| M11 | Fixed (GCP) | VPN, BGP and NAT alert policies. AWS alarms open. |
| M13, M14 | Fixed | Guards block replacement; AWS KMS and log-archive guards. |
| M15 | Design only | [ADR 0016](../adr/0016-split-aws-organization-stage.md), Proposed. |
| M16 | Changed approach | An object type drops unknown keys silently, so map inputs keep `any` and gain unknown-key validation. |
| M17 | Fixed | Removed-input shims deleted. |
| M18 | Not code | Bus factor needs a second maintainer. |
| M19 | Fixed | `tfc_admin_guard` and `no_plan_time_code_execution` OPA policies. |
| Lows | Mostly fixed | Region SCP break-glass, CloudTrail `SourceArn`, admin containment, database subnet NAT, `-e` in check-consistency, Renovate prefix, `env:` for tag values. Open: `check-jsonschema` hashes, some harden-runner jobs in audit mode, release signing, module lockfiles. |

New defects found during remediation, both fixed: the GCP KMS `key_names` output returned short names, which broke gcp-organization CMEK wiring at plan; Security Lake could not plan more than one Region.

Residual for C1: a CLI speculative plan on a workload workspace still runs with that workload's plan identity, by design. Every open residual is listed in [known gaps](../known-gaps.md#open--residual-items-from-the-2026-11-11-audit-remediation).

## Part 1: Critical

### C1. A platform-team plan can steal the tfc-admin org-admin token (VERIFIED in code; HCP behaviour as documented)

- **Evidence:**
  - `envs/tfc-admin/main.tf:553-559` and `:619-621` give the platform team custom access with `runs = "plan"` on every control-plane project, including the project that holds `tfc-admin` ("capped at plan").
  - `TFE_TOKEN` is a sensitive environment variable on that workspace (`docs/runbooks/tfc-admin-token-rotation.md:50`).
  - The only defence is `speculative_enabled = false` (`modules/tfc/workspace/main.tf:24-27`). That setting only turns off *automatic PR* plans.
- **Attack:**
  1. A platform member runs `terraform plan` from the CLI against `tfc-admin`. HCP allows CLI speculative plans on VCS-connected workspaces for anyone with `plan` permission, and the uploaded configuration is the member's own, unreviewed code.
  2. A `data "external"` or `http` block in that code reads `TFE_TOKEN` and sends it out.
  3. The token holds `manage_workspaces` and `manage_policies`. The attacker can detach policy sets, rewrite variables, and queue and confirm applies on any workspace. That bypasses the approvers team, the security-team split for `gcp-guardrails`, and CODEOWNERS.
  4. The same path reads full state on every control-plane workspace, although grants say `state_versions = "read-outputs"`.
- **Related, same root cause:**
  - **High:** fixed `write` on `saas-*` projects (`main.tf:622`) exposes the account-wide `SUPABASE_ACCESS_TOKEN` and `VERCEL_API_TOKEN` in the same way.
  - **High:** the `saas-outputs-reader` team token is `TFE_TOKEN` on non-prod bridging workloads (`envs/aws/workload/providers.tf:83-86`, `envs/gcp/workload/providers.tf:40-43`). It has `read-outputs` on *every* `saas-*` workspace (`main.tf:830-845`). Non-prod workloads keep automatic PR plans. So any PR author on a dev workload can read the prod Supabase database password.
  - **High:** nothing denies provisioners, `hashicorp/external`, `http`, or providers outside an allowlist. Not in OPA (`policies/opa/`), and not in CI. OPA runs *after* the plan, so it cannot stop exfiltration during the plan.
- **Fix:**
  - Treat `plan` as "runs arbitrary code with this workspace's secrets".
  - Set the platform team to `runs = "read"` on any project that holds static admin credentials (`tfc-admin`, `saas-*`).
  - Create one outputs-reader team per environment, scoped to the matching `saas-<env>` workspace.
  - Add a CI rule (conftest or tflint) that rejects `external`/`http` data sources and provisioners outside an allowlist.
  - Run privileged workspaces on an agent pool with egress blocked.

### C2. The default GCP hub-and-spoke fails at the second environment (VERIFIED)

- **Evidence:**
  - `envs/gcp/workload/main.tf:89-97` gives every environment the same peering key, `"hub-peering"`.
  - `modules/gcp/stages/net-spoke/main.tf:178-187` uses the key as the peering name. `create_reverse_peering` defaults to `true` (`net-spoke/variables.tf:195`, `environment/variables.tf:127`).
  - `modules/gcp/network/vpc-peering/main.tf:21-25` therefore creates `hub-peering-reverse` **on the hub VPC** from inside each `gcp-workload-<env>` state.
- **Consequence:**
  - Peering names are unique per network, so the second environment's apply collides.
  - It also fails earlier on permissions: the workload apply SA has `compute.admin` only on its own environment folder (`modules/gcp/stages/bootstrap/variables.tf:224-237`), and the hub project sits in the `shared` folder.
  - Even if both problems were fixed, a workload state would own a hub resource, which is a blast-radius inversion.
  - The sandbox runs one environment (`config/sandbox/landing-zone.yaml:67`), so this path has never been exercised.
- **Fix:** `gcp-network-hub` creates the hub-side peerings with `for_each` over the environments, with names that include the environment key. Workload roots create only their own side (`create_reverse_peering = false`). Add a two-environment fixture to the sandbox.

### C3. The GCP and AWS IP plans collide by default (VERIFIED)

- **Evidence:**
  - `docs/architecture/cidr-plan.md` reserves `10.0.0.0/12` for GCP and `10.64.0.0/10` for AWS.
  - The AWS defaults are inside the GCP block. In `envs/aws/network/variables.tf`, IPAM top is `10.0.0.0/8`, the regional pool is `10.0.0.0/12`, inspection is `10.0.0.0/16` and egress is `10.1.0.0/16`. The last two are exactly the GCP hub and DNS ranges.
  - These values are not read from `landing-zone.yaml` (`envs/aws/network/main.tf:58-61`), so VCS-driven runs always use the defaults.
  - The example config contradicts the plan: GCP prod is `10.30.0.0/16`, and AWS workloads use `10.20`/`10.40`, which is outside both the AWS block and the IPAM pool.
  - No overlap check exists anywhere.
- **Consequence:** enabling the GCP-AWS VPN or interconnect, which both hubs already ship, produces overlapping routes.
- **Fix:** read the AWS network CIDRs from config, with defaults inside `10.64.0.0/10`. Add a plan-time `check` in `tfc-admin` that fails on any overlap across every hub, DNS, environment and workload CIDR.

---

## Part 2: High

### Security

**H1. The default workload VPC-SC egress lets any identity copy data to any bucket in the world (VERIFIED).**
- **Evidence:** `modules/gcp/stages/environment/main.tf:43-55` defaults to `identity_type = "ANY_IDENTITY"`, `resources = ["*"]`, `storage.googleapis.com`, all methods. `envs/gcp/workload/variables.tf:359-375` defaults to `[]`, so this fallback always applies.
- **Consequence:** once the perimeter is enforced, any compromised principal can run `gsutil cp` to an attacker bucket in another org. That is the exfiltration path VPC-SC exists to close.
- **Fix:** default egress to `[]`. Require explicit `identities` and `projects/<n>` resources.
- **Related (SUSPECTED):** the default ingress puts a WIF pool in `sources.resource`, which accepts only projects or VPC networks.

**H2. The WIF tenant-pin constraint can be bypassed with an uploaded JWKS (VERIFIED in code; exploit not run).**
- **Evidence:** `custom.wifProviderTenantPinned` (`modules/gcp/stages/organization/main.tf:330-340`) checks only `issuerUri` and `attributeCondition`. Workload apply SAs hold `roles/iam.workloadIdentityPoolAdmin` on their folder (`modules/gcp/stages/bootstrap/variables.tf:244`).
- **Attack:** a compromised `wl-<env>-apply` creates a provider with issuer `https://app.terraform.io`, the exact pinned condition, and an attacker-owned `jwks_json`. The attacker then mints any token.
- **Fix:** add a DENY on `has(resource.oidc.jwksJson) && resource.oidc.jwksJson != ''`. Remove `workloadIdentityPoolAdmin` from default workload roles.
- **Note:** the 2026-11-06 audit listed "WIF paren bypass" as open. This is a different bypass of the same control.

**H3. Delegated folder IAM can reach owner on every prod project (VERIFIED).**
- **Evidence:** `modules/gcp/stages/organization/automation_delegation.tf:65-76` lets `projects-apply` grant `roles/resourcemanager.projectIamAdmin`, `iam.serviceAccountAdmin` and `workloadIdentityPoolAdmin`. The validation at `variables.tf:616` blocks only owner and folderAdmin.
- **Consequence:** `projects-apply` can grant itself `projectIamAdmin` on the prod folder, then `roles/owner` on any prod project.
- **Fix:** remove these roles from the delegable list, or add a `hasOnly` member condition that names the workload SAs.

**H4. Prod workloads have no four-eyes check (VERIFIED).** The platform team has fixed `write` on workload projects (`envs/tfc-admin/main.tf:622`, `:817-823`). One person can set a `TF_VAR_*` workspace variable, which beats `landing-zone.yaml`, then queue and confirm a prod apply. There is no PR, no CODEOWNERS review and no second person. **Fix:** give production workloads the control-plane treatment (`variables = "read"`, applies confirmed by the approvers team).

### System design

**H5. App services, the environment network, the perimeter and the budget share one state, driven from the central YAML (VERIFIED).**
- **Evidence:** services come from `gcp.environments.<env>.services` and `aws.workload_environments.<env>.services`, which need platform and security CODEOWNERS approval (`.github/CODEOWNERS:99`). The same root owns the spoke VPC, NAT, VPC-SC and app services (`modules/gcp/stages/environment/main.tf:77,129,148,372`).
- **Consequence:**
  - Adding one Cloud Run service needs a platform-reviewed PR.
  - That PR re-plans the environment's network.
  - A bad service config blocks network changes.
  - This is the opposite of the 2026 golden-path pattern: team-owned app stacks that consume a platform contract.
- **Fix:** add `gcp-app-<env>-<team>` and `aws-app-<env>-<team>` roots that read the workload contract. Remove `services` from `landing-zone.yaml`.

**H6. One config edit queues a plan on every workspace (VERIFIED).**
- **Evidence:** every workspace triggers on `config/landing-zone.yaml` and on all of `modules/<cloud>/**` (`envs/tfc-admin/main.tf:21-26,901`). Run triggers then fan out from the hubs to every workload.
- **Consequence:** at 50 environments, a one-line service change queues about 55 GCP plans. These include `gcp-bootstrap`, the most privileged root.
- **Fix:** split the config per layer and per environment (for example `config/gcp/envs/<env>.yaml`). Scope `trigger_patterns` to the modules each root actually composes.

**H7. GCP has no egress inspection or FQDN control (VERIFIED).** Each spoke has its own Cloud NAT straight to the internet (`net-spoke/main.tf:99-121`). No Secure Web Proxy, Cloud NGFW or `google_network_security_*` resource exists. AWS has central inspection, so the two clouds are not at parity. **Fix:** add an opt-in hub egress path (SWP or NGFW endpoints) with spoke routes through the hub.

**H8. One hub VPC-SC perimeter puts prod and non-prod together (VERIFIED).** `modules/gcp/stages/network-hub/main.tf:105-133` protects every environment's host project in one perimeter. Once that perimeter is enforced, dev and prod can exchange Storage and BigQuery data freely. **Fix:** limit the hub perimeter to the hub and DNS projects, and rely on the per-environment perimeters.

### Terraform craft

**H9. `vault-secrets` fails on any later apply in TFC (VERIFIED).**
- **Evidence:** `modules/supabase/vault-secrets/main.tf:67-76`. `npm_install` re-runs only when `package-lock.json` changes. `node_modules` is gitignored.
- **Consequence:** a later secrets change on a fresh TFC runner runs `reconcile.mjs`, which needs `pg`, without the install. The result is `ERR_MODULE_NOT_FOUND`.
- **Fix:** run `npm ci` inside the same provisioner command as bootstrap and reconcile.

**H10. `compute-dashboard` can never update after creation (VERIFIED).** `modules/gcp/monitoring/compute-dashboard/main.tf:88-92` has `ignore_changes = [dashboard_json]`, and that attribute is the dashboard's entire content. **Fix:** remove `ignore_changes`, normalise the JSON, and add a test that changes a tile.

**H11. Stage tests mostly check that mocked outputs pass through (VERIFIED).**
- **Evidence:** `modules/aws/stages/security/tests/plan_assertions.tftest.hcl` overrides 17 child modules. About 9 of its 24 asserts check that stage outputs equal the strings set in those overrides. `gcp/stages/organization` uses 45 overrides.
- **Consequence:** `override_module` throws away the inputs to child modules, so the wiring is untested. C2 is exactly this class of bug. The e2e suite covers 8 of 124 modules and no stage.
- **Fix:** mock providers instead of modules on critical wiring paths, and assert on child resources. Add one stage, two environments, to e2e.

---

## Part 3: Medium

| # | Finding | Evidence | Fix |
|---|---|---|---|
| M1 | The AWS `tfc-plan` role is `ReadOnlyAccess` minus an incomplete deny-list. API key values, launch-template user data and CodeBuild env vars stay readable to PR plans. | `modules/aws/iam/tfc-oidc-baseline/main.tf:338-375` | Build the role up from `ViewOnlyAccess`/`SecurityAudit` plus the reads that refresh needs. |
| M2 | The log-archive SCP protects 4 S3 actions. A local admin can add replication to an external bucket or swap the encryption key. | `scp-deny-tamper.json.tftpl:137-153` | Deny `s3:PutBucket*`, `PutReplicationConfiguration`, `PutEncryptionConfiguration`, `PutLifecycleConfiguration` except for privileged roles. |
| M3 | The incident-response forensics role cannot be assumed. `aws:SourceAccount` and `aws:SourceOrgID` exist only on service-principal calls. | `modules/aws/security/incident-response/main.tf:155,183` | Use `aws:PrincipalAccount` and `aws:PrincipalOrgID`. |
| M4 | Log-archive access logging targets itself, but the bucket uses SSE-KMS and an Object Lock default retention. Delivery probably fails silently (SUSPECTED). | `modules/aws/data/log-archive-bucket/main.tf:142,152,162` | Use a separate SSE-S3 access-log bucket. |
| M5 | Member admins can rewrite `tfc-apply-boundary` with `CreatePolicyVersion`. The SCP covers role actions only. | `organization-policy/main.tf` `role_tamper_actions` | Add policy-version denies on `policy/tfc-apply-boundary` to the SCP. |
| M6 | "Drift" detection is a plan diff. Merged-but-unapplied changes count as drift, and the run does not pin a configuration version. | `.github/workflows/drift-detection.yml:234-250` | Use `refresh-only` against the last applied configuration version. |
| M7 | The `pg` npm dependency runs with prod DB credentials but has no update tool. | `renovate.json:6-8` (`terraform` only), no npm in `dependabot.yml` | Add npm to Renovate and pin an exact version. |
| M8 | CI tests Terraform `1.17.1`. TFC applies with `~> 1.17`. | `envs/tfc-admin/variables.tf:523-527` | Pin an exact version in tfc-admin, bumped by Renovate together with CI. |
| M9 | The prod Cloud SQL golden path is zonal by default. | `modules/gcp/stages/app-services/variables.tf:259` | Default HA and a cross-region backup location on when `is_production`. |
| M10 | Terraform state has one copy, in HCP. An org deletion or token compromise loses all 15+ roots. | `docs/runbooks/apply-recovery.md:46-50` | Scheduled export of current state versions to a locked, versioned bucket in each cloud. |
| M11 | No data-plane alerts: VPN tunnel down, NAT port exhaustion, TGW or Network Firewall drops. | absence in `modules/*/monitoring`, `net-hub`, `network-hub` | Hub alert sets, on by default when VPN, interconnect or NAT is enabled. |
| M12 | The default GCP tenancy runs workloads in the Shared VPC host project. | `environment/main.tf:372,425` | Make `service_team` mandatory. |
| M13 | Deletion "guards" protect less than the docs say. The Cloud SQL guard has no `replace_triggered_by`. The Aurora guard cannot be turned off by a consumer. | `gcp/data/cloud-sql/main.tf:50-58`, `aws/data/rds-aurora/main.tf:129-133` | Add `replace_triggered_by`, a toggle, and correct the README. |
| M14 | AWS KMS keys and the log-archive bucket have no `prevent_destroy` or guard. GCP KMS does. | `aws/data/kms-key/main.tf:201`, `cloudtrail-org/main.tf:227` | Add a guard for parity. |
| M15 | `aws/stages/organization` is a god-module: 63 variables, 1,459 lines. Nesting is 5 levels deep on GCP workload. | measured | Split guard alerts, Config recorder and backup role out. Have stages call primitives directly. |
| M16 | `type = any` at root boundaries (9 uses). A misspelled key is dropped silently. | `envs/gcp/workload/variables.tf:154,528,630,642` | Re-declare the stage's `object({...})` type. |
| M17 | There are 81 removed-input shims at v0.1.0, and each setting is threaded through about 5 places. | `envs/gcp/organization/deprecated_inputs.tf`, 15 `config.tf` files (1,481 lines) | Delete the shims (pre-1.0). Generate root plumbing from the JSON schema. |
| M18 | Bus factor 1: 688 of 710 commits are from one person, and 67 commits since September touch audit or known-gaps docs. | `git shortlog -sn` | A second maintainer with TFC owner rights before any production use. |
| M19 | Policy-as-code does not cover the TFC layer. `tfc-admin` can detach the policy set that judges it in one apply. | `policies/opa/`, `envs/tfc-admin/main.tf:1008` | Add a mandatory policy on `tfe_policy_set`, `auto_apply` and team-access changes. |

## Part 4: Low

- One version for all 124 modules. Renovate commits as `build(deps):`, which is hidden in the changelog. No signed tags or provenance (`release-please-config.json`, `renovate.json:17`).
- `harden-runner` is in `audit` mode on jobs that hold secrets (release, drift, e2e).
- Tag-derived values go into `run:` directly (`terraform-apply.yml:195-199,221-226`). Pass them through `env:`.
- `terraform-apply.yml` applies nothing. Rename it.
- `check-jsonschema` is installed without hashes (`terraform-plan.yml:418`).
- 248 committed lockfiles in reusable modules, which callers ignore.
- `scripts/check-consistency.sh` uses `set -uo pipefail` without `-e`.
- 9 root `config.tftest.hcl` suites have no assertions.
- The region SCP exempts the management-account break-glass ARN (which SCPs never apply to), not the member one.
- The log-archive CloudTrail write grant is scoped by org ID only, with no `aws:SourceArn`.
- The GCP admin-containment deny is on only when a production environment exists (`envs/gcp/guardrails/config.tf:57`).
- The database subnet is NAT'd, and its egress deny relies on a network tag (`tiered-vpc/main.tf:385-402`).

## Genuine strengths

- **AWS guardrails are above SRA baseline:**
  - RCP tenant pins for TFC and GitHub
  - a self-propagating `tfc-apply` permissions boundary with name-squatting protection
  - KMS key policies with no root delegation and split `PutKeyPolicy`
  - a COMPLIANCE-mode Object Lock archive
- **Identity per stage and per phase on both clouds.** Prod WIF is bound by immutable workspace ID, with a hard plan failure.
- **The workspace catalog is derived, not hand-kept.** The run-trigger DAG, remote-state sharing and auto-apply eligibility all come from one inventory and fail closed.
- **GitHub Actions supply chain:**
  - every action SHA-pinned
  - `permissions: {}` by default
  - no `pull_request_target`
  - hash-locked tooling
  - a well-designed gated e2e workflow
- **Terraform hygiene:**
  - one `required_version` across 263 blocks
  - no provider blocks in modules
  - 100 `moved` blocks
  - write-only `*_wo` secrets
  - 1,309 `optional()` attributes
  - zero README drift across 124 modules

## Prioritised remediation

1. **C1:** set the platform team to `runs = "read"` on `tfc-admin` and `saas-*`. Use per-environment SaaS reader teams. Add a CI rule against `external`/`http` and provisioners. This is a small diff that closes the largest hole.
2. **C2 + H11:** move hub-side peerings into `gcp-network-hub`, and add a two-environment sandbox fixture and one stage-level e2e test.
3. **C3:** read AWS CIDRs from config, and add a cross-cloud overlap `check`.
4. **H1, H2, H3:** close the VPC-SC egress default, the JWKS bypass and the delegable `projectIamAdmin`.
5. **H4 + M19:** four-eyes review on prod workloads, and policy coverage of `tfe_*` resources.
6. **H9, H10, M3:** small, concrete bugs. Fix them now.
7. **H5, H6:** separate app roots per team, and split config per environment. This is the largest change. Write an ADR first.
