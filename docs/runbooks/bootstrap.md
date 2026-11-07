# Runbook: GCP Phase-0 Bootstrap and First-Time Stand-Up

**When to use:** You are standing up the GCP landing zone from zero — no Terraform Cloud state, no automation identity, no folders or guardrails. This is the GCP counterpart to the [AWS Bootstrap runbook](aws-bootstrap.md), and it solves the same chicken-and-egg problem: the phase-0 `gcp-bootstrap` apply *creates* the automation identity and the Terraform Cloud WIF pool that later runs use, but that first apply must run before any of them exist. The [Quick Start](../guides/QUICK_START.md) covers the same sequence at a higher level; this runbook is the detailed, code-grounded version.

**Time:** the applies take an hour or two; plan on **2–3 working days** of elapsed time for the GCP foundation (through `gcp-network-hub` plus one `gcp-workload-<env>`). Most of it is outside Terraform: org/billing access, group creation, quota and API enablement, IAM propagation, reviewing VPC-SC dry-run logs, and fixing first-apply findings.
**Risk:** High for the first apply — you run it with your **personal** organization-admin credentials, which bypass the guardrails the org root will later install. Once the WIF pools exist, revoke those personal credentials: every later run executes in Terraform Cloud with dynamic credentials (GitHub Actions only runs PR checks).
**Prerequisites:** See the out-of-band list below. You are comfortable with the [provider-selection model](../architecture/provider-selection.md) (one cloud = one root = one workspace) and the [GCP landing-zone architecture](../architecture/gcp-landing-zone.md), especially its "Out-of-band prerequisites" and "Automation identity & break-glass" sections.

---

## Overview

Where the AWS SRA spreads its foundation across seven layered roots, GCP uses **five roots**, applied in order (see the [GCP landing zone](../architecture/gcp-landing-zone.md#layer-map--which-root-deploys-what)):

1. **`envs/gcp/bootstrap`** (workspace `gcp-bootstrap`) stands up the automation foundation: the admin project, the `terraform-admin` service account, and the WIF pools. Apply it **first**. It is the phase-0 **producer** of `admin_project_id`, `admin_project_number`, `terraform_admin_email`, `suffix`, and the OIDC pool outputs (`envs/gcp/bootstrap/outputs.tf`).
2. **`envs/gcp/organization`** (workspace `gcp-organization`) **reads** the bootstrap remote state and runs the organization stage: folders, org policy, KMS, audit logging, billing. Producer of `org_id`, `folders`, `tag_values`/`tag_keys`, `cmek_key_names`, `billing_account`, and the re-exported WIF pool IDs.
3. **`envs/gcp/projects`** (workspace `gcp-projects`) **reads** gcp-organization (folders, tags, billing) and gcp-bootstrap (admin project, suffix), and vends the host/spoke projects. Producer of `project_ids`, `project_numbers`, and the `environment_config` contract that gcp-workload consumes.
4. **`envs/gcp/network-hub`** (workspace `gcp-network-hub`) **reads** gcp-projects (host project IDs) and gcp-organization (folders, org_id), and builds the hub VPC, DNS anchor, and hub VPC-SC perimeter. Producer of `hub_network`.
5. **`envs/gcp/workload`** (workspace `gcp-workload-<env>`, one per environment) **reads** gcp-projects (`environment_config`), gcp-network-hub (`hub_network`), and gcp-organization (`org_id`, `billing_account`, `admin_project_number`), and stands up that environment's Shared VPC host network + budget.

The control plane was split into separate states (bootstrap / organization / projects / network-hub) to shrink the blast radius — see [gcp-state-decomposition.md](../architecture/gcp-state-decomposition.md) (audit H3).

The wrinkle unique to GCP is in step 1: the providers **impersonate** a `terraform-admin` service account, but *that SA is created by the `gcp-bootstrap` apply itself*. So the first `gcp-bootstrap` apply cannot impersonate a SA that does not exist yet — it must run as the human `admin_email`. This runbook calls that the **two-phase first apply** and details it below.

> **No cross-root `depends_on`.** Terraform has no dependency edge between roots. Ordering across the five roots is enforced entirely by **apply order** (this runbook) plus remote-state reads: a downstream root fails at plan time with an "output not found" error if its upstream has not been applied yet.

---

## Prerequisites (out-of-band — cannot be Terraform-bootstrapped)

These must exist before you touch Terraform. None of them is created by this repo:

- [ ] **A GCP Organization + Cloud Identity / Workspace domain.** The org is looked up **by domain**, not by ID (`data.google_organization.org` with `domain = var.domain` in `envs/gcp/organization/data.tf`). The organization and its backing Cloud Identity / Google Workspace domain must already exist. Find your org: `gcloud organizations list`.
- [ ] **A billing account, linked.** Looked up via `data.google_billing_account.billing` — by ID (`billing_account`) or by display name (`billing_account_display_name`); at least one must be set (enforced by both a variable `validation` and a `lifecycle.precondition`). The account must be **open**. Creating and linking a billing account is a console/admin step. Find it: `gcloud billing accounts list`.
- [ ] **A human organization administrator.** The first apply runs as your personal ADC. You need these roles **at the organization level**: `roles/resourcemanager.organizationAdmin`, `roles/billing.admin` (or `billing.user` + project-creator), `roles/iam.organizationRoleAdmin`, `roles/orgpolicy.policyAdmin`.
- [ ] **Cloud Identity groups, created before the first org apply.** Terraform binds IAM to these groups but never creates them, so a missing group fails the apply with "group does not exist". Each needs at least one member, and two for break-glass:
  - `gcp.organization_admin_groups` and `gcp.billing_admin_groups`: the standing admin groups.
  - `gcp.break_glass_group`: exempt from the admin-containment deny policy. That policy turns on automatically once any environment is `is_production`, and the plan fails without this group.
  - Every group named in `gcp.environments[*].iam_group_role_bindings`.
- [ ] **A Terraform Cloud organization.** The `cloud` backend in `envs/gcp/organization/backend.tf` hard-codes `workspaces { name = "gcp-organization" }` but takes the TFC **organization** from the `TF_CLOUD_ORGANIZATION` environment variable (see Step 2). You need permission to create workspaces in that org.
- [ ] **(Optional) GitHub WIF values.** The GitHub WIF pool is **off by default** (`enable_github_wif = false` — no workflow in this repo uses GCP OIDC). To enable it you need the repository's immutable numeric IDs: `gh api repos/<owner>/<repo> --jq '.id, .owner.id'` → `github_repository_id`, `github_repository_owner_id` (plus `github_org` / `github_repo`). The trust keys on the IDs, not the renameable names, and binds only the read-only organization plan SA.

> **Optional — Access Context Manager policy.** VPC-SC perimeters (hub + per-env) are gated on an existing org-level ACM access policy passed as `vpc_sc_access_policy_name` (a bare numeric ID, no `accessPolicies/` prefix). With the default `null`, **no perimeter is created** and the bootstrap proceeds without it. Create the ACM policy out-of-band only if you want data perimeters from day one; find it with `gcloud access-context-manager policies list --organization=ORG_ID`.

---

## Phase-0: from zero state to a runnable `gcp-organization` apply

### Step 1 — Authenticate as the human admin

On a fresh org there is no automation identity yet, so the first run uses your personal Application Default Credentials:

```bash
gcloud auth application-default login
gcloud config set project YOUR_SEED_PROJECT
```

Enable the APIs the bootstrap needs on whatever seed project you authenticate from (the bootstrap module enables the full set on the admin project it creates, but the *initial* API calls need these on the seed project):

```bash
gcloud services enable cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  --project=YOUR_SEED_PROJECT
```

### Step 2 — Configure the TFC backend organization

The workspace name is baked into each root's `backend.tf` (an HCP Terraform `cloud {}` block). Only the TFC **organization** is supplied, from the environment. Phase-0 applies `envs/gcp/bootstrap` (workspace `gcp-bootstrap`) first, so initialise that root:

```bash
export TF_CLOUD_ORGANIZATION=YOUR_TFC_ORG_NAME
# export TF_CLOUD_HOSTNAME=app.eu.terraform.io   # only for HCP EU / Terraform Enterprise
terraform -chdir=envs/gcp/bootstrap init
```

The `gcp-bootstrap` workspace must already exist (tfc-admin pass 1, [below](#creating-and-wiring-the-tfc-workspaces-tfc-admin-two-pass)). tfc-admin creates it with **execution mode `local`** (`workspace_execution_modes` default `{ "gcp-bootstrap" = "local" }`): `terraform apply` runs on your machine with your ADC and only the state is stored in TFC. A remote run would have no GCP credentials, because the WIF pool does not exist yet.

> A `cloud` block accepts no `-backend-config` and no `backend.hcl` (Terraform rejects both). `make backend-check` proves every root's block initialises.

### Step 3 — Fill in `config/landing-zone.yaml` (and tfvars only for the rest)

The shared inputs live once in the committed `config/landing-zone.yaml`. Generate it with `scripts/init-landing-zone.sh`, or copy [`config/landing-zone.example.yaml`](../../config/landing-zone.example.yaml). Every GCP root reads it. An explicit variable (tfvars or TFC variable) still wins over the file. A value that is still unset, or still a placeholder, fails the plan with a message naming the variable and the config key. Only inputs the file does not hold need a gitignored tfvars file:

```bash
cp envs/gcp/organization/terraform.tfvars.example envs/gcp/organization/local.auto.tfvars   # optional
```

**Required for a production estate: the workspace IDs.** gcp-bootstrap binds each workspace's service accounts by immutable workspace ID. When any environment `is_production`, it refuses to bind by (squattable) name. tfc-admin pass 1 has already created the workspaces and knows their IDs. The local phase-0 run ignores workspace variables, so write the IDs into a gitignored tfvars file:

```bash
make bootstrap-ids   # = terraform -chdir=envs/tfc-admin output -raw gcp_bootstrap_tfvars > envs/gcp/bootstrap/tfc-workspaces.auto.tfvars
```

Later remote gcp-bootstrap runs get the same map as a workspace variable, set by tfc-admin.

Set at minimum (config key in brackets):

- `domain` (`org.domain`) — the org's Cloud Identity / Workspace domain (used to look up the org ID; `org_id` and `billing_account_id` are **not** input variables).
- `billing_account` (`gcp.billing_account`) **or** `billing_account_display_name` — at least one is required.
- `admin_email` (`gcp.admin_email`) and `organization_admin_groups` / `billing_admin_groups` (`gcp.organization_admin_groups` / `gcp.billing_admin_groups`) — standing admin is group-only, so at least one group each is required.
- `project_prefix` (`org.prefix`) — your real org identifier. The example's `"my-org"` is a **deliberate tripwire**: a `validation` block rejects it at plan time, and a second validation enforces the `^[a-z][a-z0-9-]{0,9}$` shape.
- (gcp-bootstrap, optional) `enable_github_wif` + `github_repository_id` / `github_repository_owner_id` — only if you want GitHub Actions OIDC (off by default, read-only SA only).
- `hub_vpc_cidr_block` and `dns_hub_vpc_cidr_block` (`gcp.network.hub_cidr_block` / `gcp.network.dns_hub_cidr_block`) — non-overlapping CIDRs for the hub and DNS-hub VPCs.
- `environments` (`gcp.environments`) — the map of environment definitions (each with `display_name`, `region`, `cidr_block`, `budget_monthly_limit`, `iam_group_role_bindings`, optional `is_production` / `labels`). The keys become folder keys, project keys, `gcp-workload-<key>` workspace names, and the `environment_config` output keys. It is defined once, and every GCP root and tfc-admin reads the same map.
- `tfc_organization` (`org.tfc.organization`) — same TFC org as the backend; needed for the TFC WIF pool.

> **Leave `terraform_admin_email` unset (null) for the first apply — and in Terraform Cloud, leave it unset forever.** In TFC each run authenticates via dynamic credentials as its phase-specific SA (audit C2); `terraform_admin_email` is only for deliberate local human runs. See the next section.

---

## The two-phase first apply (impersonation chicken-and-egg)

Both the `gcp-bootstrap` and `gcp-organization` roots use the same provider config (`providers.tf`), with `impersonate_service_account = var.terraform_admin_email`:

```hcl
provider "google" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}
```

The `terraform-admin` SA those providers want to impersonate is *created by the `gcp-bootstrap` root*. That is a bootstrap paradox: you cannot impersonate an identity that has not been created yet.

The resolution is that `terraform_admin_email` is **nullable** (default `null`, with a validation that accepts `null` or a `…iam.gserviceaccount.com` address). When it is `null`, `impersonate_service_account` is empty and the providers authenticate **directly as your personal ADC** — the human `admin_email`, who holds org-admin and can create the SA. This is intended to be used exactly once, on the first `gcp-bootstrap` apply.

**Phase 1 — apply `gcp-bootstrap` as the human admin (`terraform_admin_email = null`):**

```bash
terraform -chdir=envs/gcp/bootstrap plan
terraform -chdir=envs/gcp/bootstrap apply
```

The `gcp-bootstrap` root creates the admin project (`${project_prefix}-admin-${suffix}`, `deletion_policy = "PREVENT"`), enables its API set, creates the `terraform-admin` SA (via `modules/gcp/iam/service-account`) with your `user:${admin_email}` as an impersonation member, and provisions the WIF pools. Record the SA email from its outputs:

```bash
terraform -chdir=envs/gcp/bootstrap output -raw terraform_admin_email
# e.g. terraform-admin@ashes-admin-1a2b3c4d.iam.gserviceaccount.com
```

**Phase 2 — hand over to Terraform Cloud dynamic credentials (no impersonation).** Wire the workspaces (pass 2 of the tfc-admin flow below) so each `gcp-*` workspace gets `TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL` / `TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL` from the bootstrap outputs `tfc_plan_service_accounts` / `tfc_apply_service_accounts`, and **do not** set `terraform_admin_email` on any TFC workspace: the run already *is* the right SA, and a plan SA has no `serviceAccountTokenCreator` on the admin SA, so setting it fails closed. In the same tfc-admin apply set `workspace_execution_modes = {}` so `gcp-bootstrap` switches from `local` to `remote` and its later runs use its own plan/apply SAs. Then apply the organization root from TFC:

```bash
# queued from TFC (VCS run on main) — runs plan as <prefix>-organization-plan,
# apply as <prefix>-organization-apply
```

For a deliberate **local** human re-apply of `gcp-bootstrap` (e.g. break-glass), you can still impersonate the admin SA, because `admin_email` was granted `serviceAccountTokenCreator` on it in phase 1:

```hcl
terraform_admin_email = "terraform-admin@ashes-admin-1a2b3c4d.iam.gserviceaccount.com"
```

Once CI is wired, revoke your personal ADC:

```bash
gcloud auth application-default revoke
```

> **Do not skip phase 1's `null`.** If `terraform_admin_email` is set before the SA exists, the providers fail to impersonate a non-existent SA and the apply cannot even create it.

---

## What the control-plane roots create

The GCP control plane is four roots (audit H3), one stage each, applied in order
(`gcp-bootstrap` → `gcp-organization` → `gcp-projects` → `gcp-network-hub`). The
stages and what each creates:

**`module.bootstrap`** — the automation foundation:

- **Admin project** `${project_prefix}-admin-${random_id.suffix.hex}`, `deletion_policy = "PREVENT"`, with the full API set enabled (resourcemanager, IAM, IAM Credentials, logging, storage, orgpolicy, accesscontextmanager, securitycenter, essentialcontacts, pubsub, bigquery, monitoring, …).
- **`terraform-admin` SA**, impersonable by `user:${admin_email}`. Since audit C2 it is the identity for the phase-0 human bootstrap and the **`gcp-bootstrap` apply phase only**, holding just org `iam.securityAdmin` + org viewer (to manage every other stage SA's IAM) and SA / WIF-pool / serviceusage admin on the admin project. It no longer holds orgpolicy/ACM/logging/SCC/xpn/tag admin or billing costsManager.
- **Per-stage plan/apply SAs** (Cloud Foundation Fabric FAST pattern, `modules/gcp/stages/bootstrap/service_accounts.tf`), all in the admin project:

  | SA | TFC binding | Rights |
  |---|---|---|
  | `<prefix>-bootstrap-plan` | `gcp-bootstrap:plan` | read-only (browser, org viewer, security reviewer, SA/WIF/serviceusage viewer, billing viewer) |
  | `<prefix>-organization-plan` / `-apply` | `gcp-organization:plan` / `:apply` | plan: org read-only + policy/logging/SCC/tag/deny/contacts viewers; apply: folderAdmin, iam.securityAdmin, orgpolicy.policyAdmin, logging.configWriter, SCC notificationConfigEditor, tagAdmin/tagUser, denyAdmin, essentialcontacts.admin; KMS/GCS/PubSub/BQ/monitoring on the admin project; billing costsManager |
  | `<prefix>-projects-plan` / `-apply` | `gcp-projects:plan` / `:apply` | apply: projectCreator, billing.projectManager + billing.user, metrics-scope admin, and a **conditional** org `folderIamAdmin` that can only grant the workload/network folder roles (IAM delegated role grants) |
  | `<prefix>-network-hub-plan` / `-apply` | `gcp-network-hub:plan` / `:apply` | apply: org ACM policyAdmin; network roles on the `shared` folder (granted by gcp-projects) |
  | `<prefix>-wl-<env>-plan` / `-apply` | `gcp-workload-<env>:plan` / `:apply` | **no org-level role**: env-folder roles granted by gcp-projects, billing budget roles, and ACM rights on **its own env folder-scoped access policy** only (created by gcp-organization, `enable_scoped_access_policies`, default `true`: apply `policyEditor`, plan `policyReader`); the org-wide policy grant (`vpc_sc_access_policy_id`) applies only with the opt-in `enable_legacy_org_access_policy_grants` |

- **TFC WIF pool** `tfc-pool` (when `enable_tfc_oidc = true` and `tfc_organization != null`). The provider condition pins `terraform_organization_name` (plus `terraform_organization_id` / `terraform_project_id` when `tfc_organization_id` / `tfc_project_ids` are set) and admits only the `plan` / `apply` phases. It maps composite attributes `workspace_phase = <name>:<phase>` and `workspace_id_phase = <id>:<phase>`; each SA is bound to exactly one of them (by workspace **ID** when `tfc_workspace_ids` supplies it), so a speculative/PR plan can only ever mint a read-only identity and a squatted workspace name gains nothing once IDs are pinned.
- **GitHub WIF pool** — only when `enable_github_wif = true` (default **false**). Trust is pinned to `repository_owner_id` + `repository_id` on `refs/heads/main` and bound to the read-only `<prefix>-organization-plan` SA only.

**`module.organization`** — hierarchy & governance: org folders (one `Shared Services` folder + one per `environments` key, `prevent_destroy`), org policies (the ~15-constraint guardrail set, stricter on the `strict_folder_policy_environment_keys` folders, default `["prod"]`), tag keys/values bound per folder, one folder-scoped VPC-SC access policy per environment folder with that environment's workload SAs granted on it only (`automation_delegation.tf`), the projects-apply delegated `folderIamAdmin` bound per target folder, org-wide audit logs → CMEK GCS sink (+ BigQuery analytics), SCC Pub/Sub notifications, org CMEK keyring, org budget, and Essential Contacts.

**`module.projects`** — the shared `hub` and `dns` projects plus one `<env>-host` project per environment, all `deletion_policy = "PREVENT"`, attached to the admin metrics scope. It also grants the C2 automation identities their scoped rights: each `<prefix>-wl-<env>-plan/-apply` SA on **its own env folder** only (`workload_folder_roles`), and the network-hub SAs on the `shared` folder (`network_folder_roles`) — both lists read from gcp-bootstrap so they match the projects-apply delegation condition.

**`module.network_hub`** — the hub VPC (`hub-vpc-core`), the DNS hub (`dns-vpc-core` + private root zone), and — **only if `vpc_sc_access_policy_name` is non-null** — the hub VPC-SC perimeter protecting the spoke project numbers.

---

## Creating and wiring the TFC workspaces (tfc-admin, two-pass)

Do **not** hand-create the GCP workspaces or hand-type dynamic-credential env vars. The [`envs/tfc-admin`](../../envs/tfc-admin/README.md) root codifies the whole workspace layer: one TFC project per cloud, VCS wiring with `trigger_patterns` (`<working_dir>/**` plus the module domain the root consumes, e.g. `modules/gcp/**`), `speculative_enabled = false` on the control plane (a PR cannot obtain a privileged speculative plan), `global_remote_state = false` with an explicit consumer graph, health assessments (native drift detection), a shared `landing-zone-common` variable set, and per-workspace dynamic credentials.

Because the WIF pool and the per-workspace plan/apply service accounts are created by `gcp-bootstrap`, which itself runs in a workspace tfc-admin creates, wiring is **two-pass**:

1. **Pass 1 — workspaces only.** Create the `tfc-admin` workspace by hand once (working directory `envs/tfc-admin`, `TFE_TOKEN` as a sensitive env var holding a temporary phase-0 owner token), then apply it. **Revoke the phase-0 owner token after that first apply** and switch tfc-admin to the expiring non-owner `tfc-admin` team token described in [tfc-admin-token-rotation.md](tfc-admin-token-rotation.md); set `tfc_admin_team_id` to that team. With `gcp.enabled: true` in the committed `config/landing-zone.yaml`, tfc-admin derives the cloud flags, one `gcp-workload-<env>` per `gcp.environments` key, and the project names from that file. The explicit `enable_gcp` / `environments` variables still override it. Every cloud defaults to disabled, and at least one must be enabled. Every `gcp-*` workspace now exists with triggers, settings and remote-state sharing, but **no** `TFC_GCP_*` env vars (they are only set when their inputs are non-null). `gcp-bootstrap` is created in execution mode `local`; every other workspace is `remote`.
2. **Apply `gcp-bootstrap`** (the phase-0 human apply described above, from your machine with ADC and `terraform_admin_email` unset). It publishes `tfc_workload_provider_name` (`projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`) and the per-workspace maps `tfc_plan_service_accounts` / `tfc_apply_service_accounts` (keyed by workspace name).
3. **Pass 2 — dynamic credentials.** Either copy those outputs into the tfc-admin variables `gcp_workload_provider_name`, `gcp_plan_service_accounts`, `gcp_apply_service_accounts`, **or** set `gcp_bootstrap_outputs_from_tfc = true` to read them via `tfe_outputs` (tfc-admin is then added as a remote-state consumer of `gcp-bootstrap`). Re-apply tfc-admin. Each GCP workspace in the maps receives:

   | Env var | Value |
   |---------|-------|
   | `TFC_GCP_PROVIDER_AUTH` | `true` |
   | `TFC_GCP_WORKLOAD_PROVIDER_NAME` | the WIF provider name |
   | `TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL` | the workspace's read-only plan SA |
   | `TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL` | the workspace's apply SA |

   In the same pass set `workspace_execution_modes = {}`. That moves `gcp-bootstrap` from `local` to `remote` execution now that it has dynamic credentials.

4. Apply the remaining GCP roots in order (`gcp-organization` → `gcp-projects` → `gcp-network-hub` → `gcp-workload-<env>`) from TFC. Because control-plane workspaces have speculative plans disabled, review their plans from a run queued on `main` (or a CLI-driven plan by an operator), not from PR checks.

**VCS-driven runs get no local tfvars.** The shared inputs come from the committed `config/landing-zone.yaml`, which every root reads. Commit any other per-workspace Terraform inputs to `config/tfc-workspaces.yaml` (start from [`config/tfc-workspaces.example.yaml`](../../config/tfc-workspaces.example.yaml)); tfc-admin reads it when present (`workspace_variables_file`) and sets every entry as a workspace variable. Secrets are rejected in that file; pass them through `workspace_variables` (write-only).

The same flow applies to AWS (`aws.enabled: true`): see the [AWS bootstrap runbook](aws-bootstrap.md#step-3--create-the-aws-tfc-workspaces-with-tfc-admin-pass-1). Single-account workspaces map to an account key via the `aws-organization` output `tfc_workspace_bindings`, `aws.workload_environments[<env>].account_key` in the config file (or `environments[<env>].aws_account_key`), or `aws_workspace_account_keys`. The multi-account roots `aws-security` / `aws-backup` get the management role (`aws_management_plan_role_arn` / `aws_management_apply_role_arn`) as their default configuration and one `TFC_AWS_*_<alias>` set per member-account alias.

**GitHub Actions (release metadata / drift).** In the repo → Settings → Secrets and variables → Actions:

| Name | Type | Value |
|------|------|-------|
| `GOOGLE_PROJECT_ID` | Variable | Admin project ID (`admin_project` output) |
| `TFC_ORGANIZATION` | Variable | Your TFC org name |
| `TFC_TOKEN` | Secret | Read-only TFC team token (release run-status checks) |
| `TFC_TOKEN_DRIFT` | Secret | Queue-plans TFC team token for drift detection (no fallback to `TFC_TOKEN`) |

See [CI_SECRETS.md](../guides/CI_SECRETS.md).

> **Escape hatch — run #1 with local state.** If you want the bootstrap applied before any TFC workspace exists, run phase 1 with `terraform -chdir=envs/gcp/bootstrap init -backend=false` and a local apply, then (after tfc-admin pass 1 creates `gcp-bootstrap`) re-`init` **with** the `cloud` backend to migrate the local state into it. The default path — tfc-admin creates `gcp-bootstrap` in `local` execution mode and you apply from your machine with TFC holding state — avoids the migration.

---

## Standing up the first environment

Once `gcp-organization` is applied and its outputs are published, each application environment is a separate `gcp-workload-<env>` workspace that reads the org remote state. **Do not duplicate that procedure here** — it is fully covered in [add-environment.md](add-environment.md). In brief:

1. Add **one** entry under `gcp.environments` in `config/landing-zone.yaml` (plus any workload tfvars and their `-var-file` wiring) in one PR, and merge it.
2. Confirm the **tfc-admin** apply. It creates `gcp-workload-<env>` with its `environment` variable and, after the handover (pass 2 above, `gcp_bootstrap_outputs_from_tfc = true`), its `TFC_GCP_*` env vars: the SA emails are derived as `<org.prefix>-wl-<env>-{plan,apply}@<admin_project_id>.iam.gserviceaccount.com`, so no second tfc-admin pass is needed. Its apply triggers `gcp-bootstrap` and `aws-organization`, the DAG roots.
3. Confirm each shared workspace as its triggered run queues: **gcp-bootstrap** (creates the `<prefix>-wl-<env>-plan/-apply` SAs and their `gcp-workload-<env>:plan/:apply` WIF bindings), **gcp-organization** (the env folder), **gcp-projects** (host project and env-folder grants) and **gcp-network-hub**.
4. A workload with `is_production: false` set explicitly then applies itself from `gcp-network-hub`'s run trigger (`auto_apply_run_trigger`); any other one (production, or the flag omitted) waits for confirmation. A new AWS workload also needs a second tfc-admin pass after `aws-organization` applies, for its role ARNs. The workload reads `environment_config[<env>]` (CIDR, region, folder, host project) from the org remote state; the per-env CIDR is **not** set in the workload tfvars.

Greenfield is different: the first environment exists before any gcp-bootstrap output, so it follows the phase-0 two-pass flow above.

See [add-environment.md](add-environment.md) for the exact steps, expected plan output, and rollback.

---

## Verification

After the first `gcp-organization` apply:

```bash
# Automation foundation exists
terraform -chdir=envs/gcp/organization output -raw terraform_service_account_email
terraform -chdir=envs/gcp/organization output -json | jq '{
  github_oidc_pool_id: .github_oidc_pool_id.value,
  tfc_oidc_pool_id:    .tfc_oidc_pool_id.value
}'

# Admin project is present
gcloud projects describe "$(terraform -chdir=envs/gcp/organization output -raw admin_project)"

# Folders + org policies landed
gcloud resource-manager folders list --organization="$(terraform -chdir=envs/gcp/organization output -raw org_id)"

# Cross-root contract is published (workload roots depend on this)
terraform -chdir=envs/gcp/projects output -json environment_config | jq 'keys'
terraform -chdir=envs/gcp/network-hub output -json hub_network
```

Checklist:

- [ ] `terraform_service_account_email` resolves to `terraform-admin@<admin-project>.iam.gserviceaccount.com`.
- [ ] `github_oidc_pool_id` and `tfc_oidc_pool_id` are non-empty.
- [ ] The admin project exists and has `deletion_policy = PREVENT`.
- [ ] One folder exists per `environments` key plus `Shared Services`.
- [ ] `environment_config` keys match your `environments` keys.
- [ ] A TFC-queued plan of `gcp-organization` runs as `<prefix>-organization-plan` and its apply as `<prefix>-organization-apply` (check the run's "Dynamic credentials" log line), with `terraform_admin_email` **unset** on the workspace.
- [ ] `gcloud organizations get-iam-policy <ORG_ID> --flatten=bindings --filter='bindings.members~-wl-'` returns **nothing** (workload SAs hold no org-level role).

---

## Migrating an existing deployment to per-stage identities (audit C2)

Existing estates bound every workspace to `terraform-admin`. Re-applying gcp-bootstrap with this change **revokes** those bindings and the admin SA's stage roles in the same apply (the unchanged org-viewer / securityAdmin grants are carried over with `moved` blocks, so the admin SA is never without org IAM admin mid-apply). Until step 2 completes, the other `gcp-*` workspaces fail closed at authentication. Order:

1. **Apply `gcp-bootstrap`** (from TFC, or locally impersonating the admin SA). Its next TFC *plan* needs the plan SA — if the workspace still has only `TFC_GCP_SERVICE_ACCOUNT_EMAIL`, run this one apply locally or set `TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL` first.
2. **Apply `tfc-admin`** (pass 2) so every workspace gets `TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL` / `TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL`, and **remove** any `terraform_admin_email` Terraform variable from the TFC workspaces.
3. **Apply `gcp-projects`** — grants the workload / network SAs their folder roles. Projects created earlier by `terraform-admin` are owned by it, not by `projects-apply`; label/billing edits to those pre-existing projects may need a one-off `roles/owner` grant to `<prefix>-projects-apply` on them (validate on your org).
4. **Apply `gcp-organization`, `gcp-network-hub`, `gcp-workload-<env>`** as usual. If an enforced VPC-SC perimeter lists `terraform-admin` in `vpc_sc_ingress_identities`, add the new `<prefix>-network-hub-apply` / `<prefix>-wl-<env>-apply` SAs (`stage_service_accounts` / `workload_service_accounts` outputs) **before** step 1.
5. `tfc_workspace_ids` is set automatically. `tfc-admin` writes it onto the gcp-bootstrap workspace (`set_gcp_bootstrap_workspace_ids`), so remote runs bind WIF by immutable ID. Optionally also set `tfc_project_ids` and `tfc_organization_id`.

The unused GitHub pool is **destroyed** by default (`enable_github_wif = false`). GCP soft-deletes pools for 30 days; to re-enable within that window set a new `github_wif_pool_id`.

---

## Rollback

The bootstrap deliberately makes the foundation hard to destroy: the admin project and all created projects carry `deletion_policy = "PREVENT"`, and org folders are `prevent_destroy`. A blind `terraform destroy` on the org root will **not** tear those down and is not the intended recovery path.

- **A partial or failed first apply** is safe to re-run. Terraform is idempotent; fix the tfvars (most first-run failures are the `my-org` tripwire, `enable_github_wif = true` without the numeric repository IDs, or an unlinked/closed billing account) and re-apply.
- **To back out an environment you just added**, destroy that environment's `gcp-workload-<env>` resources with `-target` (see the [add-environment.md rollback](add-environment.md#rollback)) rather than destroying the shared org root.
- **To decommission the whole landing zone**, temporarily relax the `deletion_policy`/`prevent_destroy` guards and destroy in **reverse** order (every `gcp-workload-<env>` first, `gcp-organization` last). This is a deliberate, reviewed operation — never a routine `terraform destroy`.

---

## See also

- [AWS Bootstrap](aws-bootstrap.md) — the AWS-side phase-0 stand-up this mirrors, control-for-control.
- [Add Environment](add-environment.md) — standing up each `gcp-workload-<env>` after the org root exists.
- [GCP Landing Zone](../architecture/gcp-landing-zone.md) — folder/project model, network topology, security services, and the out-of-band prerequisites.
- [Break Glass](break-glass.md) — the standing org-admin emergency-access path (`break_glass_user`).
