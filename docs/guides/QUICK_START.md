# Quick Start Guide

This guide covers everything needed to deploy the landing zone from scratch, including the manual bootstrap sequence that must run before CI/CD exists.

---

## Pre-flight Checklist

Before running any Terraform, verify the following:

**GCP Organisation**

- [ ] You have a GCP Organization (not just a project). Find your org ID: `gcloud organizations list`
- [ ] You have a Billing Account linked to the organization. Find it: `gcloud billing accounts list`
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

**Tooling**

- [ ] `terraform version` reports `>= 1.9.8` (see `.terraform-version`)
- [ ] `gcloud version` reports `>= 450.0.0`
- [ ] `jq` installed (used by CI scripts)
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

## 4. Bootstrap First Run (manual, one-time)

The `modules/stages/bootstrap` module creates the WIF pool that GitHub Actions uses to authenticate. This creates a chicken-and-egg dependency: you need WIF to run Terraform via CI, but you need to run Terraform to create WIF. The solution is a single manual apply of the bootstrap module.

**Step 1 — Create the backend configuration file:**

```bash
cat > envs/organization/backend.hcl <<EOF
organization = "YOUR_TFC_ORG_NAME"
workspaces { name = "organization" }
EOF
```

This file is gitignored; it is never committed.

**Step 2 — Initialize:**

```bash
terraform -chdir=envs/organization init -backend-config=backend.hcl
```

**Step 3 — Create your tfvars file** (see [Variable Reference](#variable-reference) below):

```bash
cp examples/dev.tfvars envs/organization/local.auto.tfvars
# Edit local.auto.tfvars with your org_id, billing_account, github_org, github_repo
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

| Variable | Description | Example |
|----------|-------------|---------|
| `org_id` | GCP Organization ID (numbers only) | `"123456789"` |
| `billing_account` | Billing account ID | `"012345-6789AB-CDEF01"` |
| `github_org` | GitHub organization or user name | `"my-github-org"` |
| `github_repo` | GitHub repository name | `"Ashes-Devops-Tools"` |
| `project_prefix` | Short prefix for all project names (3-8 chars) | `"ashes"` |
| `terraform_admin_email` | Service account email Terraform impersonates after bootstrap | `"terraform@admin-proj.iam.gserviceaccount.com"` |

### `envs/organization` — Key Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `billing_account_display_name` | `null` | Alternative to `billing_account` — looks up by display name |
| `organization_region` | `"europe-west1"` | Primary region for KMS, logging, network hub |
| `enable_scc_notifications` | `true` | Security Command Center Pub/Sub notifications |

### `envs/apps` — Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_prefix` | Matches org root prefix | `"ashes"` |
| `environment` | Short env name (used in resource naming) | `"dev"` |
| `terraform_admin_email` | SA Terraform impersonates (from bootstrap output) | `"terraform@ashes-admin-xxxx.iam.gserviceaccount.com"` |
| `tfc_organization` | Terraform Cloud org name | `"my-tfc-org"` |

> **VPC CIDR:** The per-environment CIDR is not set here — it is read from the `organization` workspace remote state via the `environments` map in `envs/organization`. Set the CIDR block in `envs/organization/terraform.tfvars.example` under the relevant environment key.

### `envs/apps` — Key Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_cloud_armor` | `false` | Attach WAF policy to external load balancers |
| `enable_interconnect` | `false` | Provision Dedicated Interconnect VLAN attachment |
| `enable_vpn` | `false` | Provision HA-VPN tunnels |
| `owasp_sensitivity` | `2` | Cloud Armor OWASP rule sensitivity (1=strict, 4=permissive) |

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
| `make ci` | Full local pipeline (fmt + validate + lint + security + test) |

---

## Next Steps

- Read the [Architecture Overview](../architecture/ARCHITECTURE.md)
- Read the [Network Topology](../architecture/network-topology.md)
- Read the [Contributing Guide](../../CONTRIBUTING.md)
- Browse the [Runbooks](../runbooks/) for Day 2 operations
- Use `examples/` as reference configurations for each module
