# Quick Start Guide

This guide covers everything needed to deploy the landing zone from scratch, including the manual bootstrap sequence that must run before CI/CD exists.

---

## Pre-flight Checklist

Before running any Terraform, verify the following:

### GCP Organisation

- [ ] You have a GCP Organization (not just a project). Find your org ID: `gcloud organizations list`
- [ ] You have a Billing Account linked to the organization. Find it: `gcloud billing accounts list`
- [ ] You have decided on `github_org` and `github_repo` values — **these variables have no defaults** and must be set explicitly to avoid accidentally trusting the wrong GitHub org/repo when forking
- [ ] Your user account has the following roles **at the organization level**:
  - `roles/resourcemanager.organizationAdmin`
  - `roles/billing.admin` (or `roles/billing.user` + project creator rights)
  - `roles/iam.organizationRoleAdmin`
  - `roles/orgpolicy.policyAdmin`

**Required APIs on the seed project** (enable on whichever project you authenticate from initially — the bootstrap module enables them on the admin project it creates):

```bash
gcloud services enable cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  --project=YOUR_SEED_PROJECT
```

### Tooling

- [ ] `terraform version` reports `>= 1.9.8` (see `.terraform-version`)
- [ ] `gcloud version` reports `>= 450.0.0`
- [ ] `jq` installed (used by CI scripts)
- [ ] Node.js >= 18 installed (required only if using `enable_vault_secrets = true` in any `saas-workload` call)
- [ ] A Terraform Cloud account with a workspace named `organization` (or the name in your `backend.hcl`)

---

## 1. Clone the Repository

```bash
git clone https://github.com/EdwinKassier/Ashes-Devops-Tools.git
cd Ashes-Devops-Tools
```

## 2. Install Repo Tooling

```bash
make install
make pre-commit-install
```

`make install` installs repo-managed tools: TFLint, tfsec, Checkov, terraform-docs, and pre-commit at the exact versions in `.tool-versions`. Terraform itself must be installed separately — use `tfenv` or `mise` with the version in `.terraform-version`.

## 3. Authenticate to Google Cloud

```bash
gcloud auth application-default login
gcloud config set project YOUR_SEED_PROJECT
```

> **Note:** On a fresh org, you will use personal credentials for the bootstrap run only. After bootstrap creates the Workload Identity Federation (WIF) pool, all subsequent runs go through GitHub Actions using short-lived tokens — your personal credentials are no longer needed.

---

## 3a. Configure Supabase and Vercel Provider Credentials

The `modules/supabase/*` and `modules/vercel/*` modules authenticate via API tokens set in the shell environment. These must be present before `terraform init` or `terraform plan` if any root uses these modules.

**Supabase access token:**

```bash
export SUPABASE_ACCESS_TOKEN="sbp_your_token_here"
```

Generate a personal access token at [https://app.supabase.com/account/tokens](https://app.supabase.com/account/tokens). The token requires the **Manage organization** scope.

**Vercel API token:**

```bash
export VERCEL_API_TOKEN="your_vercel_token_here"
```

Generate a token at [https://vercel.com/account/tokens](https://vercel.com/account/tokens). Prefer a **team token** scoped to the target Vercel team over a personal token for org-wide deployments.

> **Note on `modules/stages/saas-workload`:** The stage module declares `supabase`, `vercel`, and `null` providers in its `required_providers` block. Terraform evaluates `required_providers` at init time regardless of feature flag values, so **all three providers must be configured** in the calling root even when `enable_vercel = false`. If you want to use Supabase without any Vercel dependency, call `modules/supabase/environment` directly — it has no Vercel provider declaration.

**Node.js requirement for vault-secrets:**

`enable_vault_secrets = true` executes a Node.js script to bootstrap and reconcile the Supabase Vault. Before the first apply with vault-secrets enabled, install the runtime dependency:

```bash
cd modules/supabase/vault-secrets/scripts
npm install
cd -
```

The `pg ^8.20.0` package connects to the Supabase session-mode pooler to execute the bootstrap SQL. CI runners (ubuntu-latest) have Node.js 18+ available by default. The `scripts/node_modules/` directory is gitignored; re-run `npm install` after a fresh clone.

---

## 4. Bootstrap First Run (manual, one-time)

The `modules/stages/bootstrap` module creates the WIF pool that GitHub Actions uses to authenticate. This creates a chicken-and-egg dependency: you need WIF to run Terraform via CI, but you need to run Terraform to create WIF. The solution is a single manual apply of the bootstrap module.

**Step 1 — Create the backend configuration file:**

```bash
cat > envs/organization/backend.hcl <<EOF
organization = "YOUR_TFC_ORG_NAME"
EOF
```

`envs/organization/backend.tf` already hardcodes `workspaces { name = "organization" }` — do not pass a `workspaces` block via `-backend-config`; a second `workspaces` value conflicts with the one baked into `backend.tf`.

This file is gitignored; it is never committed.

**Step 2 — Initialize:**

```bash
terraform -chdir=envs/organization init -backend-config=backend.hcl
```

**Step 3 — Create your tfvars file** (see [Variable Reference](#6-variable-reference) below):

```bash
cp envs/organization/terraform.tfvars.example envs/organization/local.auto.tfvars
# Edit local.auto.tfvars with your org_id, billing_account, github_org, github_repo,
# and project_prefix — the "my-org" default is a deliberate tripwire and fails validation
```

**Step 4 — Plan and apply bootstrap only:**

```bash
terraform -chdir=envs/organization plan -target=module.bootstrap
terraform -chdir=envs/organization apply -target=module.bootstrap
```

Terraform will create:

- An admin project (`{prefix}-admin-{suffix}`)
- A GitHub Actions WIF pool and provider (trusted to your repo's `main` branch)
- A Terraform Cloud WIF pool and provider

**Step 5 — Record the outputs:**

```bash
terraform -chdir=envs/organization output -json | jq '{
  github_oidc_pool_id: .bootstrap.value.github_oidc_pool_id,
  tfc_oidc_pool_id:    .bootstrap.value.tfc_oidc_pool_id
}'
```

**Step 6 — Configure GitHub repository secrets and variables:**

In your GitHub repo → Settings → Secrets and variables → Actions:

| Name | Type | Value |
|------|------|-------|
| `GOOGLE_PROJECT_ID` | Variable | Admin project ID from bootstrap output |
| `TFC_ORGANIZATION` | Variable | Your Terraform Cloud org name |
| `TFC_TOKEN` | Secret | A TFC team token scoped to "Read runs" on the `organization` workspace |

**Step 7 — Apply the rest of the organization root:**

The remaining modules (org policies, KMS, audit logs, network hub) can now be applied via CI by pushing to `main`, or manually:

```bash
terraform -chdir=envs/organization apply
```

After this apply, all future changes go through GitHub Actions. Revoke your personal ADC credentials:

```bash
gcloud auth application-default revoke
```

---

## 5. Apply Sequencing

**Always apply `envs/organization` before `envs/apps`.**

`envs/apps` reads from `envs/organization` via `terraform_remote_state`. If organization has not been applied, apps will fail at plan time with "output not found" errors.

| Step | Root | TFC Workspace | Notes |
|------|------|---------------|-------|
| 1 | `envs/organization` | `organization` | Creates shared VPC, KMS, org policies, WIF |
| 2 | `envs/apps` | `apps-{env}` (e.g. `apps-dev`) | Reads org outputs, creates spoke projects |

To plan a change to the apps environment:

```bash
# Set TF_WORKSPACE to match the TFC workspace name suffix
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps init -backend-config=backend.hcl
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps plan -var-file=examples/dev.tfvars
```

---

## 6. Variable Reference

### `envs/organization` — Required Variables

> **Note:** `org_id` and `billing_account_id` are **not input variables** — they are resolved automatically from data sources (`data.google_organization` and `data.google_billing_account`). Set `domain` and either `billing_account` or `billing_account_display_name` instead.

| Variable | Description | Example |
|----------|-------------|---------|
| `domain` | GCP organization domain name — used to look up the org ID | `"example.com"` |
| `admin_email` | Email of the organization administrator; the bootstrap SA is created under this identity | `"admin@example.com"` |
| `github_org` | GitHub organization name for WIF OIDC trust | `"my-github-org"` |
| `github_repo` | GitHub repository name (without org prefix) for WIF OIDC trust | `"my-infra-repo"` |
| `hub_vpc_cidr_block` | CIDR for the hub VPC — must not overlap with DNS hub or any spoke | `"10.0.0.0/16"` |
| `dns_hub_vpc_cidr_block` | CIDR for the DNS hub VPC — must not overlap with hub or any spoke | `"10.1.0.0/16"` |
| `environments` | Map of environment configs (region, CIDR, budget, IAM bindings) — see `terraform.tfvars.example` | _(see example)_ |

### `envs/organization` — Key Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `billing_account` | `null` | Billing account ID — required unless `billing_account_display_name` is set |
| `billing_account_display_name` | `null` | Alternative to `billing_account` — looks up by display name |
| `project_prefix` | `"my-org"` | Short prefix for all project names (1–10 chars, lowercase, starts with a letter). **Tripwire:** the default `"my-org"` is deliberately invalid — a `validation` block rejects it at plan time. You **must** change this to your real organization identifier before your first plan. |
| `default_region` | `"europe-west1"` | Primary region for KMS, logging, network hub |
| `tfc_organization` | `null` | Terraform Cloud org name for dynamic provider credentials |
| `break_glass_user` | `null` | Email granted Organization Admin in emergencies |
| `organization_admin_groups` | `[]` | Google Groups granted Organization Admin role |
| `monthly_budget_amount` | `1000` | Org-level budget alert threshold (in `budget_currency`) |
| `security_contact_email` | `null` | Email for security notifications via Essential Contacts |

### `envs/apps` — Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_prefix` | Matches org root prefix | `"ashes"` |
| `environment` | Short env name (used in resource naming); must match a key in the org root's `environments` map | `"dev"` |
| `tfc_organization` | Terraform Cloud org name — used to read organization remote state | `"my-tfc-org"` |

> **VPC CIDR:** The per-environment CIDR is not set here — it is read from the `organization` workspace remote state via the `environments` map in `envs/organization`. Set the CIDR block in `envs/organization/terraform.tfvars.example` under the relevant environment key.

### `envs/apps` — Key Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `"europe-west1"` | Default GCP region for this environment; should match the region used for its spoke/host project in the organization root |
| `terraform_admin_email` | `null` | SA to impersonate for local runs (from bootstrap output). Example: `"terraform-admin@ashes-admin-xxxx.iam.gserviceaccount.com"` |
| `enable_cloud_armor` | `false` | Attach WAF policy to external load balancers |
| `enable_owasp_rules` | `false` | Enable Cloud Armor OWASP managed rules (requires `enable_cloud_armor`) |
| `owasp_sensitivity` | `2` | Cloud Armor OWASP rule sensitivity (1=strict, 4=permissive) |
| `enable_deletion_protection` | `true` | Guard against accidental destruction of the VPC/subnets/DNS zones |
| `vpc_sc_ingress_policies` / `vpc_sc_egress_policies` | `[]` | Optional VPC Service Controls ingress/egress policies for the perimeter |

> **Host-level networking (Dedicated Interconnect, HA-VPN, explicit zone pinning):** `envs/apps` does not expose `enable_interconnect`, `enable_vpn`, or `explicit_zones` as its own variables — those are variables of the underlying `modules/host` module (`interconnects`, `enable_vpn`, `explicit_zones`). To use them, either call `modules/host` directly from a custom root, or extend `envs/apps/main.tf`'s `module "host"` call to pass them through.

---

## 7. Run Fast Local Checks

```bash
make fmt-check
make docs-check
make security
```

## 8. Run Deeper Checks

```bash
make validate-all   # requires registry.terraform.io access
make lint           # requires TFLint Google plugin (see .tool-versions)
make test           # runs all .tftest.hcl suites with mock_provider (no GCP creds needed)
```

## 9. Plan Changes

### Control Plane

```bash
make plan-organization
```

### App Environment

```bash
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars
```

---

## Verification Checklist

- [ ] `terraform version` reports `>= 1.9.8`
- [ ] `make help` prints supported commands
- [ ] `make fmt-check`, `make docs-check`, and `make security` succeed
- [ ] `make test` reports `X passed, 0 failed`
- [ ] `terraform -chdir=envs/organization init -backend-config=backend.hcl` succeeds
- [ ] Bootstrap outputs include `github_oidc_pool_id` and `tfc_oidc_pool_id`

---

## Common Commands

| Command | Description |
|:---|:---|
| `make fmt-check` | Check Terraform formatting |
| `make docs-check` | Check terraform-docs drift |
| `make security` | Run tfsec + Checkov |
| `make validate-all` | Validate all roots |
| `make lint` | Run TFLint across all roots |
| `make test` | Run all .tftest.hcl suites |
| `make plan-organization` | Plan control-plane changes |
| `make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars` | Plan an app environment |
| `make ci` | Full local pipeline (fmt-check + docs-check + validate-all + lint + test + security) |

---

## Next Steps

- Read the [Architecture Overview](../architecture/ARCHITECTURE.md)
- Read the [Network Topology](../architecture/network-topology.md)
- Read the [Contributing Guide](../../CONTRIBUTING.md)
- **Configure [Branch Protection](BRANCH_PROTECTION.md)** — apply GitHub branch protection rules before granting team access
- Browse the [Runbooks](../runbooks/) for Day 2 operations
- Use `examples/` as reference configurations for each module
