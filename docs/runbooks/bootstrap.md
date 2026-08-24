# Runbook: GCP Phase-0 Bootstrap and First-Time Stand-Up

**When to use:** You are standing up the GCP landing zone from zero — no Terraform Cloud state, no automation identity, no folders or guardrails. This is the GCP counterpart to the [AWS Bootstrap runbook](aws-bootstrap.md), and it solves the same chicken-and-egg problem: the `gcp-organization` apply *creates* the automation identity and WIF pools that CI later uses, but that first apply must run before any of them exist. The [Quick Start](../guides/QUICK_START.md) covers the same sequence at a higher level; this runbook is the detailed, code-grounded version.

**Time:** 1–2 hours for the first stand-up (mostly waiting on API enablement, project creation, and IAM propagation).
**Risk:** High for the first apply — you run it with your **personal** organization-admin credentials, which bypass the guardrails the org root will later install. Once the WIF pools exist, revoke those personal credentials and let CI take over.
**Prerequisites:** See the out-of-band list below. You are comfortable with the [provider-selection model](../architecture/provider-selection.md) (one cloud = one root = one workspace) and the [GCP landing-zone architecture](../architecture/gcp-landing-zone.md), especially its "Out-of-band prerequisites" and "Automation identity & break-glass" sections.

---

## Overview

Where the AWS SRA spreads its foundation across seven layered roots, GCP folds the same responsibilities into **two roots** (see the [GCP landing zone](../architecture/gcp-landing-zone.md#layer-map--which-root-deploys-what)):

1. **`envs/gcp/organization`** (workspace `gcp-organization`) composes four stage modules in a **single apply** — `bootstrap` → `organization` → `projects` → `network-hub`. It is the **producer** of the cross-root contract: it publishes `environment_config`, `hub_network`, `cmek_key_names`, the WIF pool IDs, and the other outputs in `envs/gcp/organization/outputs.tf`.
2. **`envs/gcp/workload`** (workspace `gcp-workload-<env>`, one per environment) **reads** the org remote state via `terraform_remote_state` and stands up that environment's Shared VPC host network + budget.

The wrinkle unique to GCP is inside step 1: the providers **impersonate** a `terraform-admin` service account, but *that SA is created by the bootstrap stage of the very same apply*. So the first apply cannot impersonate a SA that does not exist yet — it must run as the human `admin_email`. This runbook calls that the **two-phase first apply** and details it below.

> **No cross-root `depends_on`.** Terraform has no dependency edge between roots. Ordering between `gcp-organization` and each `gcp-workload-<env>` is enforced entirely by **apply order** (this runbook) plus the fact that `envs/gcp/workload` reads the org remote state and fails at plan time with an "output not found" error if `gcp-organization` has not been applied yet. Ordering *inside* the org root is by module dependency (`depends_on` on the four stage modules).

---

## Prerequisites (out-of-band — cannot be Terraform-bootstrapped)

These must exist before you touch Terraform. None of them is created by this repo:

- [ ] **A GCP Organization + Cloud Identity / Workspace domain.** The org is looked up **by domain**, not by ID (`data.google_organization.org` with `domain = var.domain` in `envs/gcp/organization/data.tf`). The organization and its backing Cloud Identity / Google Workspace domain must already exist. Find your org: `gcloud organizations list`.
- [ ] **A billing account, linked.** Looked up via `data.google_billing_account.billing` — by ID (`billing_account`) or by display name (`billing_account_display_name`); at least one must be set (enforced by both a variable `validation` and a `lifecycle.precondition`). The account must be **open**. Creating and linking a billing account is a console/admin step. Find it: `gcloud billing accounts list`.
- [ ] **A human organization administrator.** The first apply runs as your personal ADC. You need these roles **at the organization level**: `roles/resourcemanager.organizationAdmin`, `roles/billing.admin` (or `billing.user` + project-creator), `roles/iam.organizationRoleAdmin`, `roles/orgpolicy.policyAdmin`.
- [ ] **A Terraform Cloud organization.** The `cloud` backend in `envs/gcp/organization/backend.tf` hard-codes `workspaces { name = "gcp-organization" }` but takes the TFC **organization** out-of-band — via a gitignored `backend.hcl` or `TF_CLI_ARGS_init` (see backend forms below). You need permission to create workspaces in that org.
- [ ] **GitHub org/repo trust values.** `github_org` and `github_repo` have **no defaults** — this is deliberate, so a fork cannot accidentally trust the wrong repo's `main` branch. You must set both explicitly.

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

The workspace name is baked into `backend.tf`; only the TFC **organization** is supplied out-of-band. Pick **one** form:

```bash
# Form A — gitignored backend.hcl (never committed)
cat > envs/gcp/organization/backend.hcl <<EOF
organization = "YOUR_TFC_ORG_NAME"
EOF
terraform -chdir=envs/gcp/organization init -backend-config=backend.hcl
```

```bash
# Form B — TF_CLI_ARGS_init
export TF_CLI_ARGS_init="-backend-config=organization=YOUR_TFC_ORG_NAME"
terraform -chdir=envs/gcp/organization init
```

> Do **not** pass a `workspaces` block via `-backend-config` — `backend.tf` already hard-codes `workspaces { name = "gcp-organization" }`, and a second value conflicts with it.

### Step 3 — Write the tfvars file

```bash
cp envs/gcp/organization/terraform.tfvars.example envs/gcp/organization/local.auto.tfvars
```

Set at minimum:

- `domain` — the org's Cloud Identity / Workspace domain (used to look up the org ID; `org_id` and `billing_account_id` are **not** input variables).
- `billing_account` **or** `billing_account_display_name` — at least one is required.
- `project_prefix` — your real org identifier. The default `"my-org"` is a **deliberate tripwire**: a `validation` block rejects it at plan time, and a second validation enforces the `^[a-z][a-z0-9-]{0,9}$` shape.
- `github_org` and `github_repo` — no defaults; required for the WIF OIDC trust condition.
- `hub_vpc_cidr_block` and `dns_hub_vpc_cidr_block` — non-overlapping CIDRs for the hub and DNS-hub VPCs.
- `environments` — the map of environment definitions (each with `display_name`, `region`, `cidr_block`, `budget_monthly_limit`, `iam_group_role_bindings`). The keys become folder keys, project keys, `gcp-workload-<key>` workspace names, and the `environment_config` output keys.
- `tfc_organization` — same TFC org as the backend; needed for the TFC WIF pool.

> **Leave `terraform_admin_email` unset (null) for the first apply.** This is the crux of the two-phase bootstrap — see the next section. It becomes non-null on every subsequent apply.

---

## The two-phase first apply (impersonation chicken-and-egg)

Both providers in `envs/gcp/organization/providers.tf` are configured with `impersonate_service_account = var.terraform_admin_email`:

```hcl
provider "google" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}
```

The `terraform-admin` SA those providers want to impersonate is *created by* `module.bootstrap` — the first stage of this very root. That is a bootstrap paradox: you cannot impersonate an identity the apply has not created yet.

The resolution is that `terraform_admin_email` is **nullable** (default `null`, with a validation that accepts `null` or a `…iam.gserviceaccount.com` address). When it is `null`, `impersonate_service_account` is empty and the providers authenticate **directly as your personal ADC** — the human `admin_email`, who holds org-admin and can create the SA. This is intended to be used exactly once.

**Phase 1 — first apply, as the human admin (`terraform_admin_email = null`):**

```bash
# Optional but recommended: create the automation foundation first, in isolation.
terraform -chdir=envs/gcp/organization plan  -target=module.bootstrap
terraform -chdir=envs/gcp/organization apply -target=module.bootstrap

# Then apply the rest of the root (org policies, KMS, audit logs, projects, network hub):
terraform -chdir=envs/gcp/organization apply
```

`module.bootstrap` creates the admin project (`${project_prefix}-admin-${suffix}`, `deletion_policy = "PREVENT"`), enables its API set, and creates the `terraform-admin` SA (via `modules/gcp/iam/service-account`) with your `user:${admin_email}` as an impersonation member. Record the SA email from the outputs:

```bash
terraform -chdir=envs/gcp/organization output -raw terraform_service_account_email
# e.g. terraform-admin@ashes-admin-1a2b3c4d.iam.gserviceaccount.com
```

**Phase 2 — set `terraform_admin_email` and hand over to the SA.** Put that address into your tfvars (or the TFC workspace variable) so all **subsequent** applies impersonate the SA rather than running as a human:

```hcl
terraform_admin_email = "terraform-admin@ashes-admin-1a2b3c4d.iam.gserviceaccount.com"
```

Because your `admin_email` was granted impersonation on the SA in phase 1, the very next `terraform plan`/`apply` transparently switches to impersonation. Once CI is wired (below), revoke your personal ADC:

```bash
gcloud auth application-default revoke
```

> **Do not skip phase 1's `null`.** If `terraform_admin_email` is set before the SA exists, the providers fail to impersonate a non-existent SA and the apply cannot even create it.

---

## What the `gcp-organization` apply creates

A single apply of `envs/gcp/organization` composes four stages (`main.tf`):

**`module.bootstrap`** — the automation foundation:

- **Admin project** `${project_prefix}-admin-${random_id.suffix.hex}`, `deletion_policy = "PREVENT"`, with the full API set enabled (resourcemanager, IAM, IAM Credentials, logging, storage, orgpolicy, accesscontextmanager, securitycenter, essentialcontacts, pubsub, bigquery, monitoring, …).
- **`terraform-admin` SA**, impersonable by `user:${admin_email}`, and granted the org-level roles it needs (orgpolicy admin, ACM policy admin, logging admin, org viewer, `compute.xpnAdmin`, tag admin, plus `securitycenter.admin` and `iam.securityAdmin` in a separately-justified block) and `roles/billing.costsManager` at the billing account (so it can create budgets).
- **GitHub WIF pool** `github-pool` with a provider whose attribute condition is pinned to `assertion.sub == 'repo:${github_org}/${github_repo}:ref:refs/heads/main'` — i.e. **only** `refs/heads/main` of the exact org/repo can assume the admin SA.
- **TFC WIF pool** `tfc-pool` (when `enable_tfc_oidc = true` and `tfc_organization != null`), binding **each** workspace in `local.tfc_workspaces` (`gcp-organization` plus `gcp-workload-<env>` for every environment key) to the admin SA.
- A `terraform_data` guard that fails fast if TFC OIDC is on but the workspace list is empty.

**`module.organization`** — hierarchy & governance: org folders (one `Shared Services` folder + one per `environments` key, `prevent_destroy`), org policies (the ~15-constraint guardrail set, stricter on the `strict_folder_policy_environment_keys` folders, default `["prod"]`), tag keys/values bound per folder, org-wide audit logs → CMEK GCS sink (+ BigQuery analytics), SCC Pub/Sub notifications, org CMEK keyring, org budget, and Essential Contacts.

**`module.projects`** — the shared `hub` and `dns` projects plus one `<env>-host` project per environment, all `deletion_policy = "PREVENT"`, attached to the admin metrics scope.

**`module.network_hub`** — the hub VPC (`hub-vpc-core`), the DNS hub (`dns-vpc-core` + private root zone), and — **only if `vpc_sc_access_policy_name` is non-null** — the hub VPC-SC perimeter protecting the spoke project numbers.

---

## Creating and wiring the `gcp-organization` TFC workspace

You can run the first apply from your laptop (local backend then migrate, or directly against the `cloud` backend once the workspace exists), but steady-state runs happen in TFC. Create the workspace and wire OIDC:

1. **TFC workspace** named `gcp-organization` (must match `backend.tf`). Execution mode Remote (or Agent for self-hosted runners), VCS-connected to this repo, working directory `envs/gcp/organization`.
2. **TFC dynamic credentials via WIF.** The `tfc-pool` created by the bootstrap binds each workspace to the admin SA. Configure the workspace to use GCP dynamic credentials pointed at that pool/provider (the pool + provider names are published as outputs `tfc_oidc_pool_id` / `tfc_oidc_provider_name`). Follow HashiCorp's [GCP dynamic-credentials configuration](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/gcp-configuration) — the exact env-var names are TFC-versioned, so use the published doc rather than a hard-coded snippet.
3. **GitHub Actions (if CI applies the root).** In the repo → Settings → Secrets and variables → Actions, set the WIF handoff values recorded from the bootstrap outputs:

   | Name | Type | Value |
   |------|------|-------|
   | `GOOGLE_PROJECT_ID` | Variable | Admin project ID (`admin_project` output) |
   | `TFC_ORGANIZATION` | Variable | Your TFC org name |
   | `TFC_TOKEN` | Secret | A TFC team token scoped to the `gcp-organization` workspace |

> **Escape hatch — run #1 with local state.** If you prefer the org created before the workspace exists, run phase 1 with `terraform -chdir=envs/gcp/organization init -backend=false` and a local apply, then re-`init` **with** the `cloud` backend to migrate the local state into the new TFC workspace. Creating the workspace first and letting TFC run remotely is cleaner in most cases.

---

## Standing up the first environment

Once `gcp-organization` is applied and its outputs are published, each application environment is a separate `gcp-workload-<env>` workspace that reads the org remote state. **Do not duplicate that procedure here** — it is fully covered in [add-environment.md](add-environment.md). In brief:

1. Add the environment to the `environments` map in the org root tfvars and **re-apply `gcp-organization`** (this creates the env's folder + host project and registers its `gcp-workload-<env>` workspace in the WIF binding).
2. Create the `gcp-workload-<env>` TFC workspace (working directory `envs/gcp/workload`), set the `environment` Terraform variable and the `-var-file` for its tfvars.
3. Plan and apply the workload root — it reads `environment_config[<env>]` (CIDR, region, folder, host project) from the org remote state; the per-env CIDR is **not** set in the workload tfvars.

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
terraform -chdir=envs/gcp/organization output -json environment_config | jq 'keys'
terraform -chdir=envs/gcp/organization output -json hub_network
```

Checklist:

- [ ] `terraform_service_account_email` resolves to `terraform-admin@<admin-project>.iam.gserviceaccount.com`.
- [ ] `github_oidc_pool_id` and `tfc_oidc_pool_id` are non-empty.
- [ ] The admin project exists and has `deletion_policy = PREVENT`.
- [ ] One folder exists per `environments` key plus `Shared Services`.
- [ ] `environment_config` keys match your `environments` keys.
- [ ] A subsequent `terraform plan` with `terraform_admin_email` **set** runs clean via impersonation (proves phase 2 handover works).

---

## Rollback

The bootstrap deliberately makes the foundation hard to destroy: the admin project and all created projects carry `deletion_policy = "PREVENT"`, and org folders are `prevent_destroy`. A blind `terraform destroy` on the org root will **not** tear those down and is not the intended recovery path.

- **A partial or failed first apply** is safe to re-run. Terraform is idempotent; fix the tfvars (most first-run failures are the `my-org` tripwire, a missing `github_org`/`github_repo`, or an unlinked/closed billing account) and re-apply.
- **To back out an environment you just added**, destroy that environment's `gcp-workload-<env>` resources with `-target` (see the [add-environment.md rollback](add-environment.md#rollback)) rather than destroying the shared org root.
- **To decommission the whole landing zone**, temporarily relax the `deletion_policy`/`prevent_destroy` guards and destroy in **reverse** order (every `gcp-workload-<env>` first, `gcp-organization` last). This is a deliberate, reviewed operation — never a routine `terraform destroy`.

---

## See also

- [AWS Bootstrap](aws-bootstrap.md) — the AWS-side phase-0 stand-up this mirrors, control-for-control.
- [Add Environment](add-environment.md) — standing up each `gcp-workload-<env>` after the org root exists.
- [GCP Landing Zone](../architecture/gcp-landing-zone.md) — folder/project model, network topology, security services, and the out-of-band prerequisites.
- [Break Glass](break-glass.md) — the standing org-admin emergency-access path (`break_glass_user`).
