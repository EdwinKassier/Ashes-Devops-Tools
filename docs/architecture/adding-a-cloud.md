# Adding a Cloud

This document codifies the per-cloud-root contract. Follow it to add a new cloud (AWS is already scaffolded; Azure or any other provider follows the same shape). The goal: new roots are **cloned from a template, not hand-assembled**, and they wire together through remote state with no cloud credentials at validate time.

Start from a scaffold:

- `templates/aws-root/` — concrete AWS root (default + aliased provider examples).
- `templates/cloud-root/` — provider-agnostic version; the contract a new cloud fills in.

---

## 1. Root naming

One root per cloud + layer, named `envs/<cloud>-<layer>`:

```text
envs/
├── organization/         # existing GCP control plane
├── apps/                 # existing GCP per-env apps
├── aws-organization/     # AWS foundational accounts + org
├── aws-security/         # AWS security tooling / log archive
└── aws-workload/         # AWS per-env workloads (fan out by workspace)
```

The workspace name matches the root: a fixed foundational root maps to one workspace (`aws-security`); a per-env root uses a workspace **prefix** (`aws-workload-`) and selects the environment with `TF_WORKSPACE` (e.g. `TF_WORKSPACE=aws-workload-dev`).

---

## 2. One provider per root

- A **workload** root has exactly **one** default provider (`provider "aws" { region = var.aws_region }`). Workloads never fan out across accounts inside a single root — they fan out across **workspaces**.
- A **cross-account foundational** root adds one **aliased** provider **per fixed foundational account** (e.g. `security_tooling`, `log_archive`). Each alias assumes a role whose ARN comes from the `<cloud>-organization` remote state (a two-phase bootstrap: the org root creates the accounts and emits the role ARNs; downstream roots assume them). The ARNs are known at plan time, so aliased providers configure without live credentials.

See `templates/aws-root/providers.tf` for both patterns.

---

## 3. Credential-free remote state (Convention 5)

**Load-bearing for CI.** Every cross-root data lookup uses the `cloud` backend with the org supplied as a variable. Because this resolves at plan time, roots pass `terraform validate -backend=false` with **no cloud credentials** — which is exactly what the PR validation workflow does.

Use this exact `config` shape:

```hcl
data "terraform_remote_state" "aws_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "aws-organization"
    }
  }
}
```

- `organization` always comes from `var.tfc_organization` — never hard-coded, so the same root works across TFC orgs.
- `workspaces = { name = ... }` targets the upstream root's workspace by name.
- In the scaffolds this block is **commented out** so a freshly cloned root validates bare. Uncomment it when you wire the root.

---

## 4. Stable output keys are the cross-root contract

A root's `outputs.tf` re-exports its stage module's outputs. Those keys are the **API** that downstream roots consume via `terraform_remote_state`:

```hcl
# aws-organization root
output "account_role_arns" {
  value = module.organization.account_role_arns  # map: account name -> assume-role ARN
}
```

```hcl
# aws-security root reads it back
assume_role {
  role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["security_tooling"]
}
```

Keep these keys **stable**. Renaming a key breaks every root that reads it. `outputs.tf` must never be empty in a live root.

---

## 5. Discovery

New roots must be picked up automatically by CI and tooling — nothing hard-codes a root list.

- `scripts/terraform-roots.sh` — enumerates roots (any `envs/<dir>` containing a `.tf` file) plus modules and examples. CI's validate/lint/fmt matrix is driven from this, so a new `envs/<cloud>-<layer>` is validated the moment it lands.
- `scripts/active-providers.sh` — derives which provider blocks / clouds are actually configured across roots (used to decide which credentials a run needs).

Add a root by cloning a template into `envs/<cloud>-<layer>/`; both scripts discover it on the next run with no matrix edits.

---

## 6. `enable_*` flags gate features, not clouds

Within a root, `enable_*` variables toggle **features** (a Cloud Armor policy, a Vault reconciler, a Vercel project). They do **not** turn whole clouds on or off.

**Cloud selection is which workspaces you apply.** Want AWS but not the GCP hub? Apply the `aws-*` workspaces and leave the GCP ones unapplied. There is no top-level `enable_aws` switch, and there should never be one — a workspace that is never applied costs nothing and keeps each root's blast radius scoped to its own state.

---

## Checklist for a new cloud root

1. Clone `templates/aws-root/` (or `templates/cloud-root/` for a non-AWS cloud) to `envs/<cloud>-<layer>/`.
2. Set the workspace `name` (or `prefix`) in `backend.tf`.
3. Fill in `versions.tf` (floored + capped provider pin) and `providers.tf` (one default provider, aliased-per-foundational-account if cross-account).
4. Uncomment and wire the `terraform_remote_state` block(s) and the stage `module` call in `main.tf`.
5. Re-export the stage contract in `outputs.tf` (stable keys).
6. Copy `terraform.tfvars.example` to `terraform.tfvars` and set `tfc_organization`.
7. `terraform -chdir=envs/<cloud>-<layer> init -backend=false && terraform ... validate` — must be green with no cloud credentials.
