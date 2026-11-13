# Quick Start Guide

This guide covers everything needed to deploy the **GCP** landing zone from scratch, including the manual bootstrap sequence that must run before CI/CD exists.

> **Deploying AWS?** The AWS landing zone has its own phase-0 stand-up flow and credential model — see [AWS bootstrap](#4a-aws-bootstrap-separate-stand-up-flow) below and the full **[AWS Bootstrap runbook](../runbooks/aws-bootstrap.md)**. Cloud selection is which workspaces you apply, not a runtime flag: **[Provider Selection](../architecture/provider-selection.md)**.

## At a Glance

1. **Configure once:** run `scripts/init-landing-zone.sh` (or `make init ARGS="..."`), or copy [`config/landing-zone.example.yaml`](../../config/landing-zone.example.yaml) to `config/landing-zone.yaml` and edit it. This one file holds the org name and prefix, domain, Terraform Cloud organization and projects, regions, the GCP environments, the AWS accounts and workload environments, and which clouds are enabled ([section 2a](#2a-configure-the-landing-zone-one-file)).
2. **Commit it.** It holds no secrets. Every root reads it, so VCS-driven Terraform Cloud runs (which never see a local tfvars file) get their values from the repo.
3. **Apply `envs/tfc-admin`.** It creates every workspace from the same file: the enabled clouds, one `gcp-workload-<env>` / `aws-workload-<env>` per environment, and the TFC projects.
4. **Bootstrap in order:** GCP `gcp-bootstrap` → `gcp-organization` → `gcp-guardrails` (security team) → `gcp-projects` → `gcp-network-hub` → `gcp-workload-<env>` (below). AWS: the [AWS Bootstrap runbook](../runbooks/aws-bootstrap.md). Supabase and/or Vercel: the [SaaS bootstrap runbook](../runbooks/saas-bootstrap.md), which assumes the `tfc-admin` workspace from step 3 exists.

**How long it takes.** The applies themselves take minutes to an hour. The elapsed
time is set by the steps around them: organization and billing access, quota and
API enablement, group creation, IAM propagation, VPC-SC dry-run review, and
first-apply fixes. Plan on about **2–3 working days** for the GCP foundation
(through `gcp-network-hub` plus one `gcp-workload-<env>`), and about **1–2 weeks**
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

- [ ] `terraform version` reports `>= 1.17` (CI pins the version in `.terraform-version`)
- [ ] `gcloud version` reports `>= 450.0.0`
- [ ] `jq` installed (used by CI scripts)
- [ ] `aws --version` reports AWS CLI v2 (AWS only: the phase-0 CloudFormation stack, StackSets and the account checks in the AWS runbooks)
- [ ] `gh --version` (repository secrets and variables, environments, branch protection, numeric repository IDs)
- [ ] `python3 --version` reports Python 3 (CI uses 3.12) for the repo scripts, and `python3 -c 'import hcl2'` succeeds (`python-hcl2`, hash-locked in `.github/requirements/hcl2.txt`; `make install` installs it; `make consistency` needs it)
- [ ] `pre-commit --version` and `cz version` (commitizen; CI pins it in `.github/requirements/commitizen.txt`): `make yamllint`, `make markdownlint-check` and `make commit-check` need them
- [ ] `check-jsonschema --version` reports 0.39.0 (`make install` installs it; by hand: `pipx install check-jsonschema==0.39.0`; `make config-check` needs it)
- [ ] `tflint`, `terraform-docs`, `shellcheck`, `trivy` and `opa` at the versions in `.tool-versions` (`make install` checks or installs all of them except shellcheck, which `make shellcheck` runs through `uvx` when available; `make opa-test` and `make security` refuse a version mismatch)
- [ ] Optional: `uv` (`make security` then runs the exact Checkov version CI uses, and `make shellcheck` uses the pinned shellcheck)
- [ ] Node.js >= 18 installed (required only if using `enable_vault_secrets = true` in any `saas-workload` call)
- [ ] A Terraform Cloud organization with the GCP workspaces (`gcp-bootstrap`, `gcp-organization`, `gcp-guardrails`, `gcp-projects`, `gcp-network-hub` and one `gcp-workload-<env>` per environment). Create them with `envs/tfc-admin` (`gcp.enabled: true` in `config/landing-zone.yaml`, or `enable_gcp = true`; every cloud defaults to disabled). It creates `gcp-bootstrap` in **local** execution mode, so the phase-0 apply below runs on your machine with your ADC while TFC stores the state ([bootstrap runbook](../runbooks/bootstrap.md#creating-and-wiring-the-tfc-workspaces-tfc-admin-two-pass))

### HCP Terraform tier and cost

The landing zone uses these HCP Terraform features. Tiers were checked against HashiCorp's [pricing page](https://www.hashicorp.com/products/terraform/pricing) and [plan overview](https://developer.hashicorp.com/terraform/cloud-docs/overview) on 2026-11-12. The pricing page does not list most of them, so the overview and feature pages are the source. Confirm on the pricing page before you buy.

| Feature | Used for | Where | Tier needed (checked 2026-11-12) |
|---|---|---|---|
| Teams with project-level custom permissions | Platform, approvers, security, viewers, state backup | tfc-admin `*_team_id` | Essentials or above. The overview lists Teams and Custom RBAC as not available on Free |
| Two VCS-sourced OPA policy sets | Guardrails and the mandatory `destroy_guard` | tfc-admin `enable_policy_sets` (on by default for `standard` / `premium`) | Standard or Premium. The overview lists policy enforcement as not available on Free and Essentials |
| Health assessments | Native drift detection | tfc-admin `enable_health_assessments` | Standard or Premium (the health assessments page) |
| Agent pools | Node.js for Supabase vault secrets | `execution_mode = "agent"` | The documentation does not name a tier. Concurrent agent runs are listed on every tier (1 on Free and Essentials). Confirm on the pricing page |
| Audit trail API | Daily export to WORM storage ([state backup](../runbooks/state-backup.md)) | `tfc-audit-trail` workflow | Standard or Premium (the [audit trails API page](https://developer.hashicorp.com/terraform/cloud-docs/api-docs/audit-trails)). HCP Terraform keeps 14 days of audit trail, so the export must not stop for longer than that |

**Minimum for a production estate: Standard.** Free and Essentials can run the roots with `enable_policy_sets = false` and `enable_health_assessments = false`, but then no policy blocks a destructive change, and the Free tier has no teams at all. That is not a supported production setup. Set `org.tfc.plan` so tfc-admin picks the right defaults. With any production environment (`is_production: true`) and the policy sets off, the tfc-admin plan fails unless you set `org.tfc.policy_sets_waiver: { reason, expires: "YYYY-MM-DD" }` and record the risk.

**Cost.** Paid tiers bill per resource under management (RUM), rated per hour. The pricing page lists "starting at" prices of $0.10 (Essentials), $0.47 (Standard) and $0.99 (Premium) per resource per month, as checked on 2026-11-12. The Free tier is limited to 500 managed resources. Count your own resources from a sandbox apply: `terraform state list | wc -l` in each workspace. Until a sandbox has been applied the count is unknown ([known gaps](../known-gaps.md)).

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

`make install` installs repo-managed tools: TFLint, Checkov, check-jsonschema, terraform-docs, and pre-commit at the exact versions in `.tool-versions`. Install Trivy at the `.tool-versions` version too — `make security` refuses a mismatched binary (tfsec is end-of-life and no longer used). Terraform itself must be installed separately — use `tfenv` or `mise` with the version in `.terraform-version`.

## 2a. Configure the Landing Zone (one file)

```bash
scripts/init-landing-zone.sh --org-name acme --tfc-org acme --clouds gcp,aws \
  --domain acme.com --billing-account 0A1B2C-3D4E5F-6A7B8C \
  --gcp-admin-email admin@acme.com --aws-management-account 123456789012 \
  --aws-email-pattern 'aws+{key}@acme.com' --github-owner acme \
  --vcs-repo acme/landing-zone --tfc-plan standard
# SaaS: add --clouds saas --supabase-org <id> --vercel-team <id> --github-repo acme/web
# or interactively: scripts/init-landing-zone.sh
# or by hand:       cp config/landing-zone.example.yaml config/landing-zone.yaml
git add config/landing-zone.yaml && git commit -m "chore(config): landing zone"
```

The script validates the inputs the same way the Terraform variables do. It writes `config/landing-zone.yaml` and lists the placeholders still left for the clouds you enabled, such as admin groups. `--rebrand` also renames the README title. Review the environments, CIDRs and groups before you commit.

`--tfc-plan` writes `org.tfc.plan` (default `standard` with `--profile production`). With `--vcs-repo`, `standard` and `premium` turn on the OPA policy sets. A production environment without them fails the tfc-admin plan unless `org.tfc.policy_sets_waiver` is set, and the script lists this under "Still required for production".

**Production environments** (`is_production: true`, such as the scaffolded GCP `prod`) fail the plan until you choose their egress (hub proxy or a waiver) and their VPC-SC mode: see [production hardening](../runbooks/production-hardening.md) for these prerequisites.

**CI on a fresh fork.** Scheduled drift detection and sandbox E2E **fail** until they are configured ([CI secrets](CI_SECRETS.md)), because a check that never ran must not read as green. If you are not ready to configure them, set the repository variable `REAL_CLOUD_CHECKS_OPT_OUT=true` to acknowledge running without them: `gh variable set REAL_CLOUD_CHECKS_OPT_OUT --body true`.

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

> **Note on `modules/saas/stages/saas-workload`:** the stage declares the `supabase` and `vercel` providers in `required_providers`. Terraform resolves `required_providers` at init regardless of feature flags, so the calling root must configure **both** even when `enable_vercel = false` ([single-provider mode](../architecture/provider-selection.md#single-provider-mode-in-the-saas-root)). To use Supabase with no Vercel provider at all, call `modules/supabase/environment` directly.

**Node.js requirement for vault-secrets:**

`enable_vault_secrets = true` executes a Node.js script to bootstrap and reconcile the Supabase Vault. Dependencies install **automatically** at apply time — the bootstrap and reconcile scripts each run `npm ci` in `modules/supabase/vault-secrets/scripts` in the same command, before `node`. No manual step is required; the apply runner only needs **Node.js 18+ and npm** on PATH (GitHub ubuntu-latest runners have them; on HCP Terraform use an agent pool whose image includes Node.js, since the hosted worker image is not guaranteed to).

The `pg` package (pinned to exactly 8.20.0 in `modules/supabase/vault-secrets/scripts/package.json`) connects to the Supabase session-mode pooler to execute the bootstrap SQL. `scripts/node_modules/` is gitignored and rebuilt by the automated `npm ci`. To prime it locally: `npm ci --ignore-scripts --prefix modules/supabase/vault-secrets/scripts`.

---

## 4. Bootstrap First Run (manual, one-time)

The `modules/gcp/stages/bootstrap` module creates the WIF pool that GitHub Actions uses to authenticate. This creates a chicken-and-egg dependency: you need WIF to run Terraform via CI, but you need to run Terraform to create WIF. The solution is a single manual apply of the bootstrap module.

**Step 1 — Point every GCP root at your Terraform Cloud organization:**

Each root's `backend.tf` is an HCP Terraform `cloud {}` block. It hard-codes the workspace name (`gcp-bootstrap`, `gcp-organization`, `gcp-guardrails`, `gcp-projects`, `gcp-network-hub`). The per-environment `gcp-workload` root instead selects by the tags `cloud:gcp` + `layer:workload` plus `TF_WORKSPACE`. The block takes only the TFC **organization**, from the environment. Export it once for every `init`:

```bash
export TF_CLOUD_ORGANIZATION=YOUR_TFC_ORG_NAME
# export TF_CLOUD_HOSTNAME=app.eu.terraform.io   # only for HCP EU / Terraform Enterprise
```

A `cloud` block accepts no `-backend-config` and no `backend.hcl`; Terraform rejects both. `make backend-check` runs a credential-less `init` of every root to prove the blocks are valid.

**Step 2 — Initialize the roots, in apply order:**

```bash
for r in bootstrap organization guardrails projects network-hub; do
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

**Step 3b — Write the workspace IDs (production estates):**

The scaffolded config is `org.profile: production` with a `prod` environment, so `gcp-bootstrap` refuses to bind WIF by workspace name and needs the immutable IDs. The local phase-0 run ignores workspace variables, so write them from tfc-admin (applied in pass 1) into a gitignored file:

```bash
make bootstrap-ids   # terraform -chdir=envs/tfc-admin output -raw gcp_bootstrap_tfvars > envs/gcp/bootstrap/tfc-workspaces.auto.tfvars
```

Skip it only for a non-production estate. Without it the plan fails naming `production_workspaces_bound_by_id`.

**Step 4 — Apply the bootstrap root first (two-phase, as the human admin):**

The GCP control plane is four layered roots applied in order: `gcp-bootstrap` →
`gcp-organization` → `gcp-projects` → `gcp-network-hub`. The security team applies a fifth, `gcp-guardrails`, after `gcp-organization`. Bootstrap is first and is
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
  tfc_oidc_pool_id:      .tfc_oidc_pool_id.value
}'
```

**Step 6 — Configure GitHub repository secrets and variables:**

In your GitHub repo → Settings → Secrets and variables → Actions:

| Name | Type | Value |
|------|------|-------|
| `TFC_ORGANIZATION` | Variable | Your Terraform Cloud org name |
| `TFC_TOKEN` | Secret (environment `tfc-readonly`) | A TFC team token with **Read runs** on the workspaces you tag for release metadata |
| `TFC_TOKEN_DRIFT` | Secret (environment `tfc-drift`) | The token of the team set as tfc-admin `drift_team_id`: **Queue plans** and **Read state versions**, no variable access. Without it, scheduled drift detection skips and a manual run fails |
| `RELEASE_APP_ID` | Variable (environment `release`) | ID of the release GitHub App. Required: `release.yml` fails without it |
| `RELEASE_APP_PRIVATE_KEY` | Secret (environment `release`) | Private key of the release GitHub App. Required |

Optional secrets (the state backup tokens `TFC_TOKEN_STATE_BACKUP` and `TFC_TOKEN_AUDIT_TRAIL`, `DOCS_BOT_PAT`) and the full list, scopes and environment setup: [CI secrets](CI_SECRETS.md).

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
2. `gcp-guardrails` — org IAM deny policies, applied by the security team ([bootstrap runbook](../runbooks/bootstrap.md#security-team-and-gcp-guardrails))
3. `gcp-projects` — host/spoke projects, `environment_config`
4. `gcp-network-hub` — hub VPC, DNS, hub VPC-SC
5. `gcp-workload-<env>` — one per environment (see [Add Environment](../runbooks/add-environment.md))

You can preview any root locally first, e.g. `terraform -chdir=envs/gcp/projects plan`.
Once bootstrap has run, revoke your personal ADC credentials:

```bash
gcloud auth application-default revoke
```

---

## 4a. AWS Bootstrap (separate stand-up flow)

The AWS landing zone does **not** share the GCP bootstrap above. It has its own phase-0 stand-up. You create only the management account and the phase-0 roles by hand. Then you bring a runnable `aws-organization` workspace online and apply the layered roots in order (`aws-organization` → `aws-security` → `aws-network` → `aws-identity` → `aws-shared-services` → `aws-backup` → `aws-workload`). Do not create the AWS organization by hand: `aws-organization` creates it. If you already have an organization, import it with `aws.adopt` (`envs/aws/organization/adopt.tf`; [AWS brownfield adoption](../runbooks/aws-brownfield-adoption.md)). The `aws-organization` apply also registers the IAM Identity Center delegated administrator. Enable IAM Identity Center in the console after that apply and before `aws-identity`.

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
| 2a | `envs/gcp/guardrails` | `gcp-guardrails` | Org IAM deny policies (admin containment); security team only; after gcp-organization |
| 3 | `envs/gcp/projects` | `gcp-projects` | Host/spoke projects; publishes `environment_config` |
| 4 | `envs/gcp/network-hub` | `gcp-network-hub` | Hub VPC, DNS, VPC-SC; publishes `hub_network` |
| 5 | `envs/gcp/workload` | `gcp-workload-{env}` (e.g. `gcp-workload-dev`) | Reads env config + hub network, builds the spoke |

To plan a change to the gcp-workload environment:

```bash
# Set TF_WORKSPACE to the full TFC workspace name (TF_CLOUD_ORGANIZATION exported as above)
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload init
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload plan
```

---

## 6. Variable Reference

Each root's full input list (name, type, default, description) is generated from its
`variables.tf` into the root's README by `make docs`, and `make docs-check` (CI) fails when
it is stale. Most inputs are optional because they default to a key in
`config/landing-zone.yaml`; the description of each input names that key.

| Root | Workspace | Inputs |
|---|---|---|
| `envs/gcp/bootstrap` | `gcp-bootstrap` | [README](../../envs/gcp/bootstrap/README.md#inputs) |
| `envs/gcp/organization` | `gcp-organization` | [README](../../envs/gcp/organization/README.md#inputs) |
| `envs/gcp/guardrails` | `gcp-guardrails` | [README](../../envs/gcp/guardrails/README.md#inputs) |
| `envs/gcp/projects` | `gcp-projects` | [README](../../envs/gcp/projects/README.md#inputs) |
| `envs/gcp/network-hub` | `gcp-network-hub` | [README](../../envs/gcp/network-hub/README.md#inputs) |
| `envs/gcp/workload` | `gcp-workload-<env>` | [README](../../envs/gcp/workload/README.md#inputs) |
| `envs/tfc-admin` | `tfc-admin` | [README](../../envs/tfc-admin/README.md#inputs) |

The values operators most often look for, and where they really live:

| Setting | Set it in `config/landing-zone.yaml` | Or as a variable on |
|---|---|---|
| Org admin email | `gcp.admin_email` | `gcp-organization`: `gcp_overrides.admin_email` |
| Org admin groups | `gcp.organization_admin_groups` | `gcp-organization`: `gcp_overrides.organization_admin_groups` |
| Break-glass group | `gcp.break_glass_group` | `gcp-organization`: `gcp_overrides.containment_exempt_principals` |
| Security contact (Essential Contacts) | (no config key) | `gcp-organization`: `gcp_overrides.security_contact_email` |
| Break-glass user | (no config key) | `gcp-organization`: `gcp_overrides.break_glass_user` |

`gcp_overrides` is one object variable on `gcp-organization`. A setting such as
`admin_email` is **not** a separate workspace variable there: a workspace variable with that
name configures nothing. Set every key you need in the same `gcp_overrides` value, because a
later value replaces the whole object ([presets README](../../examples/presets/README.md)).
Hybrid connectivity (HA VPN, Interconnect) is configured under `gcp.network.vpn` and
`gcp.network.interconnect`; the VPN pre-shared key is the write-only `vpn_shared_secret_wo`
variable on `gcp-network-hub` ([hybrid connectivity runbook](../runbooks/gcp-hybrid-connectivity.md)).

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
make plan-gcp-workload APP_ENV=dev
```

### Any other root

Any root: `make plan-gcp-<root>` or `make plan-aws-<root>` (a read-only plan in HCP Terraform). The AWS workload roots take `make plan-aws-workload APP_ENV=<env>`. Local `make apply-*` targets refuse for every root: applies run in HCP Terraform.

---

## Verification Checklist

- [ ] `terraform version` reports `>= 1.17`
- [ ] `make help` prints supported commands
- [ ] `make fmt-check`, `make docs-check`, and `make security` succeed
- [ ] `make test` reports `X passed, 0 failed`
- [ ] `terraform init` succeeds for all six GCP roots (`bootstrap`, `organization`, `guardrails`, `projects`, `network-hub`, `workload`)
- [ ] Bootstrap outputs include `tfc_oidc_pool_id` (and `github_oidc_pool_id` only if you enabled `enable_github_wif`)

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
| `make plan-gcp-workload APP_ENV=dev` | Plan an app environment (add `APP_VARS=examples/dev.tfvars.example` for local tuning knobs) |
| `make ci-quick` | The fast offline subset of `make ci`, no `terraform init`: fmt-check, consistency, config-check, scaffold-fixtures-check, count-check, links, examples-refs, required-checks, shellcheck, test-scripts, docs-check (needs check-jsonschema) |
| `make ci` | Every workstation-runnable CI gate: `ci-quick`, then yamllint, markdownlint-check, zizmor, commit-check, module-api, codeowners-check, backend-check, validate-all, lint, test, opa-test, security (needs pre-commit, cz, uv for zizmor, check-jsonschema, opa 1.22.2 and a fetched origin/main) |

---

## Next Steps

- Read the [Architecture Overview](../architecture/ARCHITECTURE.md)
- Read the [Network Topology](../architecture/network-topology.md)
- Standing up AWS? Read the [AWS Landing Zone](../architecture/aws-landing-zone.md) and the [AWS Bootstrap runbook](../runbooks/aws-bootstrap.md)
- Standing up Supabase or Vercel? Read the [SaaS bootstrap runbook](../runbooks/saas-bootstrap.md)
- Read the [Contributing Guide](../../CONTRIBUTING.md)
- **Configure [Branch Protection](BRANCH_PROTECTION.md)** — apply GitHub branch protection rules before granting team access
- Browse the [Runbooks](../runbooks/) for Day 2 operations
- Use `examples/` as reference configurations for each module
