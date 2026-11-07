# Adding a Cloud

This document codifies the per-cloud-root contract. Follow it to add a new cloud (AWS is already scaffolded; Azure or any other provider follows the same shape). The goal: new roots are **cloned from a template, not hand-assembled**, and they wire together through remote state with no cloud credentials at validate time.

Start from a scaffold:

- `templates/aws/root/` — concrete AWS root (default + aliased provider examples).
- `templates/shared/cloud-root/` — provider-agnostic version; the contract a new cloud fills in.

---

## 1. Root naming

One root per cloud + layer, named `envs/<cloud>/<layer>`:

```text
envs/
├── gcp/
│   ├── organization/     # existing GCP control plane
│   └── workload/         # existing GCP per-env apps
└── aws/
    ├── organization/     # AWS foundational accounts + org
    ├── security/         # AWS security tooling / log archive
    └── workload/         # AWS per-env workloads (fan out by workspace)
```

The workspace name matches the root: a fixed foundational root maps to one workspace (`aws-security`); a per-env root uses a workspace **prefix** (`aws-workload-`) and selects the environment with `TF_WORKSPACE` (e.g. `TF_WORKSPACE=aws-workload-dev`).

---

## 2. One provider per root

- A **workload** root has exactly **one** default provider (`provider "aws" { region = var.aws_region }`). Workloads never fan out across accounts inside a single root — they fan out across **workspaces**.
- A **cross-account foundational** root adds one **aliased** provider **per fixed foundational account** (e.g. `security_tooling`, `log_archive`). Each alias assumes a role whose ARN comes from the `<cloud>-organization` remote state (a two-phase bootstrap: the org root creates the accounts and emits the role ARNs; downstream roots assume them). The ARNs are known at plan time, so aliased providers configure without live credentials.

See `templates/aws/root/providers.tf` for both patterns.

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

## 4. One `contract` output is the cross-root API

A producer root publishes **one** output, `contract`: a non-sensitive object
holding every key downstream roots may consume. Downstream roots read
`terraform_remote_state` `.outputs.contract` and nothing else:

```hcl
# aws-organization root
locals {
  contract = {
    account_ids       = module.aws_organization.account_ids
    account_role_arns = module.aws_organization.account_role_arns # account key -> assume-role ARN
  }
}

output "contract" {
  value = local.contract
}
```

```hcl
# a downstream aws root reads it back
account_ids = data.terraform_remote_state.aws_organization[0].outputs.contract.account_ids
```

The rules:

- **Never put a sensitive value in `contract`.** One sensitive attribute moves
  the whole object into `tfe_outputs`' `sensitive_values`, out of tfc-admin's
  reach.
- **Keep the keys stable.** Renaming a key breaks every root that reads it.
- **Use one override type per upstream.** Each consumer's `<layer>_contract`
  variable has the same type as every other consumer of that upstream. A field
  that only some consumers need is `optional`, and those consumers check it in
  a validation.

`scripts/check-contracts.sh` (`make consistency`) checks that every producer
has a non-sensitive `contract`, that consumers read only `contract`, and that
the override types match. Add a new producer root to its `PRODUCERS` list. `outputs.tf` must never be empty in a
live root.

---

## 5. Discovery

New roots must be picked up automatically by CI and tooling — nothing hard-codes a root list.

- `scripts/terraform-roots.sh` — enumerates roots (any `envs/<dir>` containing a `.tf` file) plus modules and examples. CI's validate/lint/fmt matrix is driven from this, so a new `envs/<cloud>/<layer>` is validated the moment it lands.
- `scripts/active-providers.sh` — derives which provider blocks / clouds are actually configured across roots (used to decide which credentials a run needs).

Add a root by cloning a template into `envs/<cloud>/<layer>/`; both scripts discover it on the next run with no matrix edits.

---

## 6. `enable_*` flags gate features, not clouds

Within a root, `enable_*` variables toggle **features** (a Cloud Armor policy, a Vault reconciler, a Vercel project). They do **not** turn whole clouds on or off.

**Cloud selection is which workspaces you apply.** Want AWS but not the GCP hub? Apply the `aws-*` workspaces and leave the GCP ones unapplied. There is no top-level `enable_aws` switch, and there should never be one — a workspace that is never applied costs nothing and keeps each root's blast radius scoped to its own state.

---

## 7. Register the workspace in the tfc-admin catalog

`envs/tfc-admin` builds the whole TFC workspace layer from **one** local,
`local.catalog` in `envs/tfc-admin/main.tf`. The workspace set, the run-trigger
DAG, the remote-state consumer graph, the multi-account alias env vars and the
management-default list are all derived from it, so a new root is one entry.
Nothing else in `envs/tfc-admin` lists workspace names.

```hcl
# envs/tfc-admin/main.tf, inside local.catalog
"aws-observability" = {
  dir       = "envs/aws/observability"
  cloud     = "aws" # must be a key of module_paths / catalog_cloud_enabled
  desc      = "AWS central observability"
  tags      = ["cloud:aws", "layer:control-plane"] # layer:control-plane|bootstrap|workload
  upstreams = ["aws-organization"]                 # run triggers: direct edges only
  reads     = ["aws-organization"]                 # every terraform_remote_state it reads
  # Optional:
  # aws_member_aliases     = ["log_archive"] # one TFC_AWS_*_<alias> set per provider alias
  # aws_management_account = true            # default provider is the management account
  # per_environment        = true            # expand to <key>-<env> per environment;
  #                                          # use "{env}" in desc / tags
}
```

- `upstreams` are run-trigger sources. List only the direct parents (the DAG's
  transitive reduction), or a downstream run is queued once per ancestor. The
  tfc-admin workspace name (`var.tfc_admin_workspace_name`) as an upstream marks
  a phase-0 DAG root.
- `reads` must match the root's `data "terraform_remote_state"` blocks. A read
  that is not listed is denied, because `global_remote_state` is false.
- The keys pinned by `envs/tfc-admin/tests/catalog.tftest.hcl` must not change
  for existing entries: a renamed key moves every `tfe_workspace`, run trigger
  and grant. Extend the literal lists there for the new name.

A **new cloud** (not only a new root) also needs these in `envs/tfc-admin`: a
`module_paths` entry (the module domains it consumes), a `catalog_cloud_enabled`
entry (its `enable_<cloud>` gate), a `catalog_environments` entry (`[]` without
per-environment workspaces), and a `project_name_keys` entry in `config.tf`.

### AWS: add the workspace to the OIDC trust in the same change

Each member account's `tfc-plan` / `tfc-apply` role, created by
`modules/aws/iam/tfc-oidc-baseline`, trusts a literal list of workspace names
(`organization:<org>:project:<project>:workspace:<ws>:run_phase:<phase>`). A new
AWS workspace that is not in that list is denied at
`AssumeRoleWithWebIdentity`. The names come from `aws-organization`:

- **Foundational root in a member account:** add it to
  `local.default_workspace_bindings` in `envs/aws/organization/config.tf`
  (account key => workspace names), e.g.
  `log_archive = ["aws-security", "aws-observability"]`.
- **Per-environment workload:** nothing to edit. Each
  `aws.workload_environments.<env>.account_key` in `config/landing-zone.yaml`
  binds `aws-workload-<env>` to that account (`local.cfg.workload_bindings`),
  the same source tfc-admin expands `aws-workload` from.
- **Explicit override:** an `aws-organization` that sets
  `var.tfc_workspace_bindings` replaces both derivations, so add the new name
  there too.
- **Management-default root** (`aws_management_account = true`): add it to
  `tfc_management_workspaces` in `modules/aws/stages/organization/variables.tf`
  (with an `apply_policy_json`; only aws-security and aws-backup have built-in
  policies), and add its `sub` to the phase-0 management-role trust
  (`docs/runbooks/aws-bootstrap.md`, Step 2) until its dedicated role exists.
- **Member aliases** (`aws_member_aliases`): each alias is an account key, so
  that account's binding must list the workspace as well.

Apply `aws-organization` (the StackSet updates the trusts) before the new
workspace's first run.

---

## Checklist for a new cloud root

1. Clone `templates/aws/root/` (or `templates/shared/cloud-root/` for a non-AWS cloud) to `envs/<cloud>/<layer>/`.
2. Set the workspace `name` (or `prefix`) in `backend.tf`.
3. Fill in `versions.tf` (floored + capped provider pin) and `providers.tf` (one default provider, aliased-per-foundational-account if cross-account).
4. Uncomment and wire the `terraform_remote_state` block(s) and the stage `module` call in `main.tf`.
5. Re-export the stage contract in `outputs.tf` as one non-sensitive `contract` output (stable keys).
6. Copy `terraform.tfvars.example` to `terraform.tfvars` and set `tfc_organization`.
7. `terraform -chdir=envs/<cloud>/<layer> init -backend=false && terraform ... validate` — must be green with no cloud credentials.
