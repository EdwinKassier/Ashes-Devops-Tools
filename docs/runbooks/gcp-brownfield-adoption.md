# Runbook — Adopt an Existing GCP Organization (Brownfield)

The GCP roots normally **create** the environment folders, projects and org-level IAM. In an
organization that already has them, a greenfield apply fails with `alreadyExists` errors (folders
and projects) or tries to recreate resources you are running workloads in. This runbook imports
what exists instead, using `import` blocks with `for_each` (Terraform 1.7 or later; this repo
requires `~> 1.11`).

> **Status: not yet validated against a live organization.** Mock providers cannot import. The
> resource addresses below are taken from the modules, but run the first plan against a
> non-production organization (or a sandbox folder) and read it in full. Never apply a GCP root
> locally; run the plan from your pipeline or HCP Terraform, per `CLAUDE.md`.

## 1. Decide what Terraform will own

| Existing thing | Adopt it? | Notes |
|---|---|---|
| Folders whose display names match the `environments` keys in `config/landing-zone.yaml` | Yes | The folder resource is `prevent_destroy`. Keys must match exactly. |
| Folders with other names | No | Leave unmanaged, or add them to `environments` first. |
| Projects that the landing zone would create (`<prefix>-<env>-<name>-<suffix>`) | Yes, if the IDs match | The ID is built from `project_prefix`, the environment key, the project name and the bootstrap `suffix`. If your IDs differ, do not adopt. Keep them out of `environments`. |
| Org IAM bindings for org admins and billing admins | Yes | They are additive `*_iam_member` resources; an import is optional but avoids a noisy create. |
| Existing org policies, VPC-SC, firewall policies | No | Review against the plan's guardrails by hand, then retire the old ones. |

The `gcp-bootstrap` phase-0 root (admin project, Terraform admin SA, WIF pools) is not adopted. Run
it normally; see the [bootstrap runbook](bootstrap.md).

## 2. Collect the IDs

```bash
gcloud organizations list
gcloud resource-manager folders list --organization=ORG_ID --format="table(displayName,name)"
gcloud projects list --filter="parent.id=FOLDER_ID" --format="table(projectId,projectNumber)"
```

## 3. Folders: `envs/gcp/organization`

Folders are created by `google_folder.ou_folders`, keyed by `environments` key, inside
`modules/gcp/iam/organization`, which `modules/gcp/stages/organization` calls as `module.organization`
(the root `envs/gcp/organization` calls the stage as `module.organization`). Add an untracked or
committed `envs/gcp/organization/imports.tf`:

```hcl
locals {
  # environment key (as in config/landing-zone.yaml) => numeric folder ID
  adopt_folder_ids = {
    prod    = "111111111111"
    staging = "222222222222"
    shared  = "333333333333"
  }
}

import {
  for_each = local.adopt_folder_ids
  to       = module.organization.module.organization.google_folder.ou_folders[each.key]
  id       = "folders/${each.value}"
}
```

Org IAM members (optional), one entry per `org_admin_members` / `billing_admin_members` value:

```hcl
locals {
  adopt_org_id         = "123456789012"
  adopt_org_admins     = ["group:gcp-org-admins@example.com"]
  adopt_billing_admins = ["group:gcp-billing-admins@example.com"]
}

import {
  for_each = toset(local.adopt_org_admins)
  to       = module.organization.module.organization.google_organization_iam_member.org_admins[each.key]
  id       = "${local.adopt_org_id} roles/resourcemanager.organizationAdmin ${each.key}"
}

import {
  for_each = toset(local.adopt_billing_admins)
  to       = module.organization.module.organization.google_organization_iam_member.billing_admins[each.key]
  id       = "${local.adopt_org_id} roles/billing.admin ${each.key}"
}
```

The stage address assumes the call sites at the time of writing (`envs/gcp/organization/main.tf`
`module "organization"`, `modules/gcp/stages/organization/main.tf` `module "organization"`). Confirm
with `terraform plan`: a wrong address fails with a clear "configuration for import target does not
exist" error.

## 4. Projects: `envs/gcp/projects`

`modules/gcp/stages/projects` creates every project through `module "project"`, keyed
`<environment key>-<project key>`. The root calls the stage as `module.projects`. In
`envs/gcp/projects/imports.tf`:

```hcl
locals {
  # "<environment key>-<project key>" => project ID
  adopt_projects = {
    "prod-app"     = "acme-prod-app-a1b2"
    "shared-hub"   = "acme-shared-hub-a1b2"
  }
  # Services already enabled on those projects (var.project_services).
  adopt_project_services = {
    for pair in setproduct(keys(local.adopt_projects), var.project_services) :
    "${pair[0]}|${pair[1]}" => { project = pair[0], service = pair[1] }
  }
}

import {
  for_each = local.adopt_projects
  to       = module.projects.module.project[each.key].google_project.this
  id       = "projects/${each.value}"
}

import {
  for_each = local.adopt_project_services
  to       = module.projects.module.project[each.value.project].google_project_service.this[each.value.service]
  id       = "${local.adopt_projects[each.value.project]}/${each.value.service}"
}
```

The `google_project_service` imports assume `var.project_services` in `envs/gcp/projects` lists
every service already enabled on the adopted projects; services outside that list are left alone,
and listed services that are not yet enabled show as creates. The ID suffix is the `suffix`
output of `gcp-bootstrap` (`bootstrap_contract.suffix` when contracts are used); the project ID is
`<project_prefix>-<env>-<project>-<suffix>`, so a project created before the bootstrap suffix existed
will not match and must not be adopted.

Adopt a project only if its ID, folder and billing account match the plan's values. The module sets
`auto_create_network = false` and `deletion_policy = "PREVENT"`; on an adopted project these show as
in-place updates (`deletion_policy` is Terraform-only, so no API call). Remove the
`google_project_service` import block if you would rather let the plan enable the missing services.

## 5. Plan, review, apply

Run the `gcp-organization` plan, then `gcp-projects`, from your pipeline. Expect `import` actions for
each declared resource and **in-place updates** where live settings differ (labels, billing
account). Stop if the plan shows:

- **a folder or project `must be replaced`:** the display name, project ID or parent differs from
  the config. Fix the config, never accept a replace. The folder has `prevent_destroy`, and a
  project replace would delete a live project.
- **a project moving folder:** the live parent differs from `folders[<env>]`. Move it deliberately
  in GCP, or change the config.
- **an import ID error:** folder IDs are numeric (`folders/123`), project IDs are the string ID, and
  org IAM IDs are `"<org id> <role> <member>"` with the full `group:` or `user:` prefix.

After the apply, the `imports.tf` files can stay: import blocks for resources already in state are
no-ops. Remove them once the estate is stable to keep the roots tidy.

## Rollback

Imports change nothing in GCP. If the first plan looks wrong, delete `imports.tf`. To make Terraform
forget an adopted resource without destroying it, use a `removed` block with
`lifecycle { destroy = false }`. Never `terraform destroy` an adopted organization or project.
