# Quick Start Guide

This guide covers everything needed to deploy the **GCP** landing zone from scratch, including the manual bootstrap sequence that must run before CI/CD exists.

> **Deploying AWS?** The AWS landing zone has its own phase-0 stand-up flow and credential model — see [AWS bootstrap](#4a-aws-bootstrap-separate-stand-up-flow) below and the full **[AWS Bootstrap runbook](../runbooks/aws-bootstrap.md)**. Cloud selection is which workspaces you apply, not a runtime flag: **[Provider Selection](../architecture/provider-selection.md)**.

## At a Glance

1. **Configure once:** run `scripts/init-landing-zone.sh` (or `make init ARGS="..."`), or copy [`config/landing-zone.example.yaml`](../../config/landing-zone.example.yaml) to `config/landing-zone.yaml` and edit it. This one file holds the org name and prefix, domain, Terraform Cloud organization and projects, regions, the GCP environments, the AWS accounts and workload environments, and which clouds are enabled ([section 2a](#2a-configure-the-landing-zone-one-file)).
2. **Commit it.** It holds no secrets. Every root reads it, so VCS-driven Terraform Cloud runs (which never see a local tfvars file) get their values from the repo.
3. **Apply `envs/tfc-admin`.** It creates every workspace from the same file: the enabled clouds, one `gcp-workload-<env>` / `aws-workload-<env>` per environment, and the TFC projects.
4. **Bootstrap in order:** GCP `gcp-bootstrap` → `gcp-organization` → `gcp-projects` → `gcp-network-hub` → `gcp-workload-<env>` (below). AWS: the [AWS Bootstrap runbook](../runbooks/aws-bootstrap.md).

**How long it takes.** The applies themselves take minutes to an hour. The elapsed
time is set by the steps around them: organization and billing access, quota and
API enablement, group creation, IAM propagation, VPC-SC dry-run review, and
first-apply fixes. Plan on about **2–3 working days** for the GCP foundation
(through `gcp-network-hub` plus one `gcp-workload-<env>`), and about **a week**
for the AWS landing zone (account creation and the manual console gates in the
[AWS Bootstrap runbook](../runbooks/aws-bootstrap.md)).

---

## Pre-flight Checklist

Before running any Terraform, verify the following:

### GCP Organisation

- [ ] You have a GCP Organization (not just a project). Find your org ID: `gcloud organizations list`
- [ ] You have a Billing Account linked to the organization. Find it: `gcloud billing accounts list`
- [ ] (Only if you will turn on the optional GitHub WIF pool, `enable_github_wif = true`; it is off by default) you have the repository's immutable numeric IDs: `gh api repos/<owner>/<repo> --jq '.id, .owner.id'` gives `github_repository_id` and `github_repository_owner_id`
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

- [ ] `terraform version` reports `>= 1.11` (CI pins the version in `.terraform-version`)
- [ ] `gcloud version` reports `>= 450.0.0`
- [ ] `jq` installed (used by CI scripts)
- [ ] Node.js >= 18 installed (required only if using `enable_vault_secrets = true` in any `saas-workload` call)
- [ ] A Terraform Cloud organization with the five GCP workspaces: `gcp-bootstrap`, `gcp-organization`, `gcp-projects`, `gcp-network-hub` and one `gcp-workload-<env>` per environment. Create them with `envs/tfc-admin` (`gcp.enabled: true` in `config/landing-zone.yaml`, or `enable_gcp = true`; every cloud defaults to disabled). It creates `gcp-bootstrap` in **local** execution mode, so the phase-0 apply below runs on your machine with your ADC while TFC stores the state ([bootstrap runbook](../runbooks/bootstrap.md#creating-and-wiring-the-tfc-workspaces-tfc-admin-two-pass))

---

## 1. Clone the Repository

```bash
git clone https://github.com/<your-org>/<your-repo>.git
cd <your-repo>
```

## 2. Install Repo Tooling

```bash
make install
make pre-commit-install
```

`make install` installs repo-managed tools: TFLint, Checkov, terraform-docs, and pre-commit at the exact versions in `.tool-versions`. Install Trivy at the `.tool-versions` version too — `make security` refuses a mismatched binary (tfsec is end-of-life and no longer used). Terraform itself must be installed separately — use `tfenv` or `mise` with the version in `.terraform-version`.

## 2a. Configure the Landing Zone (one file)

```bash
scripts/init-landing-zone.sh --org-name acme --clouds gcp,aws \
  --domain acme.com --billing-account 0A1B2C-3D4E5F-6A7B8C \
  --gcp-admin-email admin@acme.com --aws-management-account 123456789012
# or interactively: scripts/init-landing-zone.sh
# or by hand:       cp config/landing-zone.example.yaml config/landing-zone.yaml
git add config/landing-zone.yaml && git commit -m "config: landing zone"
```

The script validates the inputs the same way the Terraform variables do. It writes `config/landing-zone.yaml` and lists the placeholders still left (AWS root emails, admin groups). `--rebrand` also renames the README title. Review the environments, CIDRs and groups before you commit.

How the roots read it:

- **Precedence:** an explicit variable (tfvars, `TF_VAR_*`, a TFC workspace or variable-set variable) > `config/landing-zone.yaml` > the root's built-in default. Existing tfvars keep working unchanged.
- **Single source:** `environments` (GCP roots and tfc-admin), `project_prefix`, `landing_zone_name`, `tfc_organization`, regions, the AWS account map and the workload-env → account-key mapping are no longer duplicated across roots.
- **Fail fast:** a value that is still unset, or still an upstream placeholder (`my-org`, `REPLACE_WITH_*`, `@example.com` root emails), fails the plan. The error names the variable and the config key.
- **Optional:** with no `config/landing-zone.yaml`, every root behaves as before. Each root's `landing_zone_config_path` variable points elsewhere, and `""` disables the lookup.
- **Per-workspace overrides** still go in [`config/tfc-workspaces.yaml`](../../config/tfc-workspaces.example.yaml), which tfc-admin writes as workspace variables. Those win over the config file.

---

## 3. Authenticate to Google Cloud

```bash
gcloud auth application-default login
gcloud config set project YOUR_SEED_PROJECT
```

> **Note:** On a fresh org, you will use personal credentials for the bootstrap run only. After bootstrap creates the Terraform Cloud Workload Identity Federation (WIF) pool and the per-stage plan/apply service accounts, every later plan and apply runs **in Terraform Cloud** with dynamic (short-lived) credentials. GitHub Actions only runs the PR checks; it holds no GCP credentials. Your personal credentials are no longer needed.

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

> **Note on `modules/saas/stages/saas-workload`:** The stage module declares `supabase`, `vercel`, and `null` providers in its `required_providers` block. Terraform evaluates `required_providers` at init time regardless of feature flag values, so **all three providers must be configured** in the calling root even when `enable_vercel = false`. If you want to use Supabase without any Vercel dependency, call `modules/supabase/environment` directly — it has no Vercel provider declaration.

**Node.js requirement for vault-secrets:**

`enable_vault_secrets = true` executes a Node.js script to bootstrap and reconcile the Supabase Vault. Dependencies install **automatically** at apply time — a `null_resource.npm_install` runs `npm ci` in `modules/supabase/vault-secrets/scripts` before the bootstrap/reconcile scripts. No manual step is required; the apply runner only needs **Node.js 18+ and npm** on PATH (CI runners on ubuntu-latest have them).

The `pg ^8.20.0` package connects to the Supabase session-mode pooler to execute the bootstrap SQL. `scripts/node_modules/` is gitignored and rebuilt by the automated `npm ci`. To prime it locally: `npm ci --prefix modules/supabase/vault-secrets/scripts`.

---

## 4. Bootstrap First Run (manual, one-time)

The `modules/gcp/stages/bootstrap` module creates the WIF pool that GitHub Actions uses to authenticate. This creates a chicken-and-egg dependency: you need WIF to run Terraform via CI, but you need to run Terraform to create WIF. The solution is a single manual apply of the bootstrap module.

**Step 1 — Point every GCP root at your Terraform Cloud organization:**

Each root's `backend.tf` is an HCP Terraform `cloud {}` block. It hard-codes the workspace name (`gcp-bootstrap`, `gcp-organization`, `gcp-projects`, `gcp-network-hub`). The per-environment `gcp-workload` root instead selects by the tags `cloud:gcp` + `layer:workload` plus `TF_WORKSPACE`. The block takes only the TFC **organization**, from the environment. Export it once for every `init`:

```bash
export TF_CLOUD_ORGANIZATION=YOUR_TFC_ORG_NAME
# export TF_CLOUD_HOSTNAME=app.eu.terraform.io   # only for HCP EU / Terraform Enterprise
```

A `cloud` block accepts no `-backend-config` and no `backend.hcl`; Terraform rejects both. `make backend-check` runs a credential-less `init` of every root to prove the blocks are valid.

**Step 2 — Initialize the roots, in apply order:**

```bash
for r in bootstrap organization projects network-hub; do
  terraform -chdir=envs/gcp/$r init
done
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload init
```

**Step 3 — Bootstrap-only inputs** (see [Variable Reference](#6-variable-reference) below):

`project_prefix`, `domain`, `billing_account`, `admin_email`, `tfc_organization`, `default_region` and `environments` already come from `config/landing-zone.yaml`. Only the bootstrap-specific inputs that are not in the config file need a local tfvars file:

```bash
cp envs/gcp/bootstrap/terraform.tfvars.example envs/gcp/bootstrap/local.auto.tfvars
# Keep only what config/landing-zone.yaml does not hold (enable_tfc_oidc, the
# optional enable_github_wif + github_repository_id / github_repository_owner_id,
# ...). Delete the rest: an explicit variable overrides the config.
```

**Step 4 — Apply the bootstrap root first (two-phase, as the human admin):**

The GCP control plane is four roots applied in order: `gcp-bootstrap` →
`gcp-organization` → `gcp-projects` → `gcp-network-hub`. Bootstrap is first and is
special: its providers can impersonate a `terraform-admin` service account that
the bootstrap apply itself creates. For this phase-0 local apply leave
`terraform_admin_email` unset (`null`) so Terraform runs as your own ADC. Every
later run happens in Terraform Cloud with dynamic credentials, and there it stays
unset too (the run already *is* the right service account). Set it only for a
deliberate local break-glass re-apply. The [bootstrap runbook](../runbooks/bootstrap.md)
has the full two-phase detail.

```bash
terraform -chdir=envs/gcp/bootstrap plan
terraform -chdir=envs/gcp/bootstrap apply
```

Terraform will create:

- An admin project (`{prefix}-admin-{suffix}`)
- The `terraform-admin` service account the other roots impersonate
- A GitHub Actions WIF pool and provider, only with `enable_github_wif = true` (off by default; it trusts the repository's numeric IDs on `main` and binds only the read-only plan SA)
- A Terraform Cloud WIF pool and provider

**Step 5 — Record the bootstrap outputs:**

```bash
terraform -chdir=envs/gcp/bootstrap output -json | jq '{
  admin_project_id:      .admin_project_id.value,
  terraform_admin_email: .terraform_admin_email.value,
  github_oidc_pool_id:   .github_oidc_pool_id.value,
  tfc_oidc_pool_id:      .tfc_oidc_pool_id.value
}'
```

**Step 6 — Configure GitHub repository secrets and variables:**

In your GitHub repo → Settings → Secrets and variables → Actions:

| Name | Type | Value |
|------|------|-------|
| `GOOGLE_PROJECT_ID` | Variable | Admin project ID from the bootstrap output |
| `TFC_ORGANIZATION` | Variable | Your Terraform Cloud org name |
| `TFC_TOKEN` | Secret | A TFC team token scoped to "Read runs" on the GCP workspaces |

**Step 7 — Wire dynamic credentials (tfc-admin pass 2) and apply the remaining roots in order, in Terraform Cloud:**

Re-apply `envs/tfc-admin` with `gcp_bootstrap_outputs_from_tfc = true` (or copy the
bootstrap outputs `tfc_workload_provider_name` / `tfc_plan_service_accounts` /
`tfc_apply_service_accounts` into its variables) and `workspace_execution_modes = {}`.
Every GCP workspace now gets its `TFC_GCP_*` env vars and `gcp-bootstrap` switches
to remote execution. Do **not** set `terraform_admin_email` on any workspace.
Shared inputs already come from the committed `config/landing-zone.yaml`. Commit any
remaining per-workspace inputs to `config/tfc-workspaces.yaml` (see
[`config/tfc-workspaces.example.yaml`](../../config/tfc-workspaces.example.yaml)),
because VCS-driven runs never see a local tfvars file. Then apply the remaining roots
**in Terraform Cloud** (never locally — see
[CLAUDE.md → State & Apply Rules](../../CLAUDE.md#state--apply-rules)): merge to `main`
for VCS-driven runs, or queue a run on each workspace in order. Each root reads the
previous one's remote state, so wait for each apply to finish:

1. `gcp-organization` — folders, org policies, KMS, audit logging, billing
2. `gcp-projects` — host/spoke projects, `environment_config`
3. `gcp-network-hub` — hub VPC, DNS, hub VPC-SC
4. `gcp-workload-<env>` — one per environment (see [Add Environment](../runbooks/add-environment.md))

You can preview any root locally first, e.g. `terraform -chdir=envs/gcp/projects plan`.
Once bootstrap has run, revoke your personal ADC credentials:

```bash
gcloud auth application-default revoke
```

---

## 4a. AWS Bootstrap (separate stand-up flow)

The AWS landing zone does **not** share the GCP bootstrap above. It has its own phase-0 stand-up: creating the AWS organization out-of-band, then bringing a runnable `aws-organization` workspace online, then applying the layered roots in order (`aws-organization` → `aws-security` → `aws-network` → `aws-identity` → `aws-shared-services` → `aws-backup` → `aws-workload`). IAM Identity Center is enabled/delegated between the organization and security/identity layers.

**AWS credentials:** the AWS roots authenticate via Terraform Cloud dynamic (OIDC) credentials (`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_PLAN_ROLE_ARN`, `TFC_AWS_APPLY_ROLE_ARN`, plus a `TFC_AWS_*_<alias>` set per member account on `aws-security` / `aws-backup`) or, for local runs, `AWS_PROFILE`. `envs/tfc-admin` (`aws.enabled: true` in `config/landing-zone.yaml`) creates the AWS workspaces and writes those env vars: the hand-created management roles via `aws_management_plan_role_arn` / `aws_management_apply_role_arn`, and the member-account roles from the `aws-organization` outputs. Every AWS root requires `landing_zone_name` (no built-in default; set `org.name` in `config/landing-zone.yaml`). Only the roots you apply pull in credentials; an unapplied workspace needs none (see the env-var table in [CLAUDE.md](../../CLAUDE.md#required-environment-variables)).

> Full phase-0 procedure, prerequisites, and layer-by-layer apply order: **[AWS Bootstrap runbook →](../runbooks/aws-bootstrap.md)**. To add an account/environment later: **[AWS Add Account →](../runbooks/aws-add-account.md)**.

---

## 5. Apply Sequencing

**Always apply `envs/gcp/organization` before `envs/gcp/workload`.**

`envs/gcp/workload` reads from `envs/gcp/projects` (`environment_config`), `envs/gcp/network-hub` (`hub_network`), and `envs/gcp/organization` via `terraform_remote_state`. Apply the four control-plane roots first, in order; otherwise apps fail at plan time with "output not found" errors.

| Step | Root | TFC Workspace | Notes |
|------|------|---------------|-------|
| 1 | `envs/gcp/bootstrap` | `gcp-bootstrap` | Admin project, Terraform admin SA, WIF pools (apply first, as the human admin) |
| 2 | `envs/gcp/organization` | `gcp-organization` | Folders, org policies, KMS, audit logging, billing |
| 3 | `envs/gcp/projects` | `gcp-projects` | Host/spoke projects; publishes `environment_config` |
| 4 | `envs/gcp/network-hub` | `gcp-network-hub` | Hub VPC, DNS, VPC-SC; publishes `hub_network` |
| 5 | `envs/gcp/workload` | `gcp-workload-{env}` (e.g. `gcp-workload-dev`) | Reads env config + hub network, builds the spoke |

To plan a change to the gcp-workload environment:

```bash
# Set TF_WORKSPACE to the full TFC workspace name (TF_CLOUD_ORGANIZATION exported as above)
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload init
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload plan -var-file=../../../examples/dev.tfvars
```

---

## 6. Variable Reference

Any variable below that maps to a `config/landing-zone.yaml` key (shown in brackets) may be left out of tfvars. An explicit variable still wins.

### `envs/gcp/bootstrap` — Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `domain` (`org.domain`) | GCP organization domain name — used to look up the org ID | `"example.com"` |
| `admin_email` (`gcp.admin_email`) | Email of the organization administrator | `"admin@example.com"` |
| `project_prefix` (`org.prefix`) | Short prefix for all project names, shared by every GCP root | `"acme"` |
| `tfc_organization` (`org.tfc.organization`) | Terraform Cloud org name, for the TFC WIF provider | `"my-tfc-org"` |

### `envs/gcp/organization` — Required Variables

> **Note:** `org_id` and `billing_account_id` are **not input variables** — they are resolved automatically from data sources (`data.google_organization` and `data.google_billing_account`). Set `domain` and either `billing_account` or `billing_account_display_name` instead.

| Variable | Description | Example |
|----------|-------------|---------|
| `domain` (`org.domain`) | GCP organization domain name — used to look up the org ID | `"example.com"` |
| `admin_email` (`gcp.admin_email`) | Email of the organization administrator | `"admin@example.com"` |
| `environments` (`gcp.environments`) | Map of environment configs (region, CIDR, budget, IAM bindings). Defined once in the config file and read by every GCP root | *(see example)* |
| `organization_admin_groups` (`gcp.organization_admin_groups`) | Google Groups granted Organization Admin (at least one, unless `allow_user_principals_for_break_glass`) | `["gcp-org-admins@example.com"]` |

### `envs/gcp/network-hub` — Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `hub_vpc_cidr_block` (`gcp.network.hub_cidr_block`) | CIDR for the hub VPC — must not overlap with DNS hub or any spoke | `"10.0.0.0/16"` |
| `dns_hub_vpc_cidr_block` (`gcp.network.dns_hub_cidr_block`) | CIDR for the DNS hub VPC — must not overlap with hub or any spoke | `"10.1.0.0/16"` |

### `envs/gcp/organization` — Key Optional Variables

| Variable | Default (or config key) | Description |
|----------|---------|-------------|
| `billing_account` | `null` | Billing account ID — required unless `billing_account_display_name` is set |
| `billing_account_display_name` | `null` | Alternative to `billing_account` — looks up by display name |
| `project_prefix` | `org.prefix` | Short prefix for all project names (1–10 chars, lowercase, starts with a letter). **Tripwire:** the example config's `"my-org"` is deliberately invalid — a `validation` block rejects it at plan time. You **must** change it to your real organization identifier before your first plan. |
| `default_region` | `org.regions.gcp`, else `"europe-west2"` | Primary region for KMS, logging, network hub |
| `tfc_organization` | `org.tfc.organization` | Terraform Cloud org name for dynamic provider credentials |
| `break_glass_user` | `null` | Email granted Organization Admin in emergencies |
| `monthly_budget_amount` | `1000` | Org-level budget alert threshold (in `budget_currency`) |
| `security_contact_email` | `null` | Email for security notifications via Essential Contacts |

### `envs/gcp/workload` — Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_prefix` (`org.prefix`) | Matches org root prefix | `"acme"` |
| `environment` | Short env name (used in resource naming); must match a key in `gcp.environments`. tfc-admin sets it from the workspace name | `"dev"` |
| `tfc_organization` (`org.tfc.organization`) | Terraform Cloud org name — used to read organization remote state | `"my-tfc-org"` |

> **VPC CIDR:** The per-environment CIDR is not set here — it comes from the `environments` map (its `cidr_block`), which flows into the `environment_config` published by `gcp-projects` and consumed by `gcp-workload`. The `environments` map is defined once, under `gcp.environments` in `config/landing-zone.yaml`, and every GCP root reads it from there.

### `envs/gcp/workload` — Key Optional Variables

| Variable | Default (or config key) | Description |
|----------|---------|-------------|
| `region` | `gcp.environments[<env>].region`, else `org.regions.gcp`, else `"europe-west2"` | Default GCP region for this environment |
| `terraform_admin_email` | `null` | SA to impersonate for deliberate local break-glass runs only (from bootstrap output). Leave `null` for the phase-0 apply and on every TFC workspace. Example: `"terraform-admin@acme-admin-xxxx.iam.gserviceaccount.com"` |
| `enable_cloud_armor` | preset, else `false` | Create the environment Cloud Armor policy (implied by public ingress) |
| `enable_owasp_rules` | preset, else `false` | Enable Cloud Armor OWASP managed rules (requires `enable_cloud_armor`) |
| `vpc_sc_enable_dry_run` | preset, else `true` | Keep the environment perimeter in dry-run; the `prod-gcp-workload` preset enforces it |
| `public_ingress_services` | `gcp.workload.public_ingress.<env>` | Services to expose on a global external ALB with a managed certificate ([guide](deploying-a-service.md#exposing-the-service-front-door)) |
| `app_bootstrap_image` | `gcp.workload.bootstrap_image`, else the public Cloud Run sample | First-revision image; set a mirror inside the VPC-SC perimeter |
| `owasp_sensitivity` | `2` | Cloud Armor OWASP rule sensitivity (1=strict, 4=permissive) |
| `enable_deletion_protection` | `true` | Guard against accidental destruction of the VPC/subnets/DNS zones |
| `vpc_sc_ingress_policies` / `vpc_sc_egress_policies` | `[]` | Optional VPC Service Controls ingress/egress policies for the perimeter |

> **Host-level networking (Dedicated Interconnect, HA-VPN, explicit zone pinning):** `envs/gcp/workload` does not expose `enable_interconnect`, `enable_vpn`, or `explicit_zones` as its own variables — those are variables of the underlying `modules/gcp/stages/host` module (`interconnects`, `enable_vpn`, `explicit_zones`). To use them, either call `modules/gcp/stages/host` directly from a custom root, or extend `envs/gcp/workload/main.tf`'s `module "host"` call to pass them through.

---

## 7. Run Fast Local Checks

```bash
make fmt-check
make docs-check
make count-check   # README/CLAUDE.md counts match the tree
make links         # no broken relative Markdown links
make security      # Trivy + Checkov at the CI-pinned versions
```

## 8. Run Deeper Checks

```bash
make validate-all   # requires registry.terraform.io access
make lint           # requires the TFLint google + aws ruleset plugins (tflint --init)
make test           # runs all .tftest.hcl suites with mock_provider (no GCP creds needed)
```

## 9. Plan Changes

### Control Plane

```bash
make plan-gcp-organization
```

### App Environment

```bash
make plan-gcp-workload APP_ENV=dev APP_VARS=examples/dev.tfvars
```

---

## Verification Checklist

- [ ] `terraform version` reports `>= 1.11`
- [ ] `make help` prints supported commands
- [ ] `make fmt-check`, `make docs-check`, and `make security` succeed
- [ ] `make test` reports `X passed, 0 failed`
- [ ] `terraform init` succeeds for all five GCP roots (`bootstrap`, `organization`, `projects`, `network-hub`, `workload`)
- [ ] Bootstrap outputs include `github_oidc_pool_id` and `tfc_oidc_pool_id`

---

## Common Commands

| Command | Description |
|:---|:---|
| `make fmt-check` | Check Terraform formatting |
| `make docs-check` | Check terraform-docs drift |
| `make security` | Run Trivy + Checkov |
| `make validate-all` | Validate all roots |
| `make lint` | Run TFLint across all roots |
| `make test` | Run all .tftest.hcl suites |
| `make plan-gcp-organization` | Plan control-plane changes |
| `make plan-gcp-workload APP_ENV=dev APP_VARS=examples/dev.tfvars` | Plan an app environment |
| `make ci` | Full local pipeline (fmt-check + consistency + count-check + links + shellcheck + docs-check + validate-all + lint + test + security) |

---

## Next Steps

- Read the [Architecture Overview](../architecture/ARCHITECTURE.md)
- Read the [Network Topology](../architecture/network-topology.md)
- Standing up AWS? Read the [AWS Landing Zone](../architecture/aws-landing-zone.md) and the [AWS Bootstrap runbook](../runbooks/aws-bootstrap.md)
- Read the [Contributing Guide](../../CONTRIBUTING.md)
- **Configure [Branch Protection](BRANCH_PROTECTION.md)** — apply GitHub branch protection rules before granting team access
- Browse the [Runbooks](../runbooks/) for Day 2 operations
- Use `examples/` as reference configurations for each module
