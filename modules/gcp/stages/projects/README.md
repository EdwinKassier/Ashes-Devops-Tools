# Projects Stage Module

> **Platform Infrastructure Projects Only**
> This module creates **platform/infrastructure projects** (VPC hosts, network hubs, shared services).
> For **application/workload projects**, use [`modules/gcp/stages/workload`](../workload/README.md) instead.

## Purpose

Creates foundational infrastructure projects at the **organization layer** for:
- **Host Projects**: VPC hosts for each declared application environment
- **Shared Projects**: Network hub, DNS hub, logging sinks
- **Infrastructure Projects**: Any platform-managed projects defined in `var.environments`

## When to Use This vs Workload Factory

| Aspect | `stages/projects` (this) | `stages/workload` |
|--------|--------------------------|-------------------|
| **Owner** | Platform Team | Application Teams |
| **Lifecycle** | Created at org setup | Created on-demand |
| **Location** | `envs/gcp/organization/` | `examples/workloads/` |
| **Purpose** | Infrastructure backbone | Application deployments |
| **Examples** | `apps-host`, `shared-hub`, `dns-hub` | `api-service`, `payments-service` |

## How It Works

```text
envs/gcp/organization/main.tf
    │
    └── module "projects" (this module)
            │
            ├── <env>-host   ─→ Used by envs/gcp/workload (gcp-workload-<env>)
            ├── shared-hub   ─→ Network connectivity hub
            └── shared-dns   ─→ DNS resolution hub
```

## Usage

This module is invoked **once** in `envs/gcp/organization/main.tf`:

```hcl
module "projects" {
  source = "../../modules/gcp/stages/projects"

  project_prefix          = var.project_prefix
  organization_name       = var.organization_name
  default_billing_account = data.google_billing_account.billing.id
  admin_project_id        = module.bootstrap.admin_project_id
  folders                 = module.organization.folders
  environments            = local.project_environments
  project_services        = var.project_services

  suffix = module.bootstrap.suffix

  depends_on = [module.organization]
}
```

## Features

- **Bulk Creation**: Creates all infrastructure projects from a single variable
- **Consistent Naming**: `{prefix}-{env}-{name}-{suffix}` format
- **Monitoring Scope**: Auto-registers projects with central monitoring
- **API Enablement**: Enables standard APIs across all projects

## Outputs

| Output | Description |
|--------|-------------|
| `project_ids` | Map of `{env}-{name}` → project ID |
| `projects` | Full project resource objects |

## Migrating state (raw `google_project` -> project primitive)

Projects are now created by the shared [project primitive](../../project/README.md)
(`module.project["<env>-<project>"]`). Because `moved` blocks cannot iterate:

- `envs/gcp/projects/moved.tf` moves the built-in `shared-hub` / `shared-dns`
  projects automatically.
- Each per-environment host project (`<env>-host`) must be moved once, before the
  first plan, from the `envs/gcp/projects` working directory:

  ```bash
  for env in dev staging prod; do   # every key in var.environments
    terraform state mv \
      "module.projects.google_project.projects[\"${env}-host\"]" \
      "module.projects.module.project[\"${env}-host\"].google_project.this"
  done
  ```

  (TFC: run it locally against the remote workspace with a temporarily unlocked
  state, or lock the workspace and use `terraform state pull` / `push`.)
- APIs (`google_project_service.project_services`) are forgotten by a `removed`
  block and re-adopted by the module — both sides use `disable_on_destroy =
  false`, so no API is ever disabled.

If a host project is not moved, the plan shows destroy + create; the destroy
fails on `deletion_policy = PREVENT` and nothing is lost.

## See Also

- [Workload Factory](../workload/README.md) - For application/service projects

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	admin_project_id =
	default_billing_account =
	environments =
	folders =
	organization_name =
	project_prefix =
	suffix =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |

## Modules


- project - ../../project


## Resources

The following resources are created:


- resource.google_folder_iam_member.network_sa_folder_roles (modules/gcp/stages/projects/main.tf#L112)
- resource.google_folder_iam_member.workload_sa_folder_roles (modules/gcp/stages/projects/main.tf#L103)
- resource.google_monitoring_monitored_project.projects (modules/gcp/stages/projects/main.tf#L63)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_project_id"></a> [admin\_project\_id](#input\_admin\_project\_id) | Project ID of the bootstrap admin project used as the metrics scope for monitoring | `string` | n/a | yes |
| <a name="input_default_billing_account"></a> [default\_billing\_account](#input\_default\_billing\_account) | Default GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX, used when a project does not specify its own billing account | `string` | n/a | yes |
| <a name="input_environments"></a> [environments](#input\_environments) | Map of environment definitions keyed by environment name. Each environment must have at least one project. | <pre>map(object({<br/>    display_name = string<br/>    description  = string<br/>    projects = map(object({<br/>      name            = string<br/>      billing_account = optional(string)<br/>      labels          = map(string)<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_folders"></a> [folders](#input\_folders) | Map of folder objects keyed by environment name, as output by the organization stage | <pre>map(object({<br/>    id           = string<br/>    name         = string<br/>    display_name = string<br/>  }))</pre> | n/a | yes |
| <a name="input_organization_name"></a> [organization\_name](#input\_organization\_name) | Organization name applied as a label on all created projects | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Short prefix applied to all project IDs for global uniqueness (e.g., 'my-org') | `string` | n/a | yes |
| <a name="input_suffix"></a> [suffix](#input\_suffix) | Random suffix from bootstrap module appended to project IDs for uniqueness | `string` | n/a | yes |
| <a name="input_network_folder_key"></a> [network\_folder\_key](#input\_network\_folder\_key) | Key in var.folders of the folder holding the hub/DNS projects (network-hub SAs are granted roles there). | `string` | `"shared"` | no |
| <a name="input_network_folder_roles"></a> [network\_folder\_roles](#input\_network\_folder\_roles) | Roles granted to the network-hub SAs on the shared/network folder ({ plan, apply }); read from the gcp-bootstrap output network\_folder\_roles. | <pre>object({<br/>    plan  = list(string)<br/>    apply = list(string)<br/>  })</pre> | <pre>{<br/>  "apply": [],<br/>  "plan": []<br/>}</pre> | no |
| <a name="input_network_service_accounts"></a> [network\_service\_accounts](#input\_network\_service\_accounts) | The network-hub stage { plan, apply } SA emails (gcp-bootstrap output stage\_service\_accounts["network-hub"]). Granted var.network\_folder\_roles on the var.network\_folder\_key folder. Null = no grants. | <pre>object({<br/>    plan  = string<br/>    apply = string<br/>  })</pre> | `null` | no |
| <a name="input_project_services"></a> [project\_services](#input\_project\_services) | List of GCP APIs to enable on every created project | `list(string)` | <pre>[<br/>  "cloudresourcemanager.googleapis.com",<br/>  "compute.googleapis.com",<br/>  "serviceusage.googleapis.com",<br/>  "iam.googleapis.com",<br/>  "cloudbilling.googleapis.com",<br/>  "monitoring.googleapis.com"<br/>]</pre> | no |
| <a name="input_workload_folder_roles"></a> [workload\_folder\_roles](#input\_workload\_folder\_roles) | Roles granted to each workload SA on its environment folder ({ plan, apply }). Must match the gcp-bootstrap delegation allow-list (read it from the gcp-bootstrap output workload\_folder\_roles). | <pre>object({<br/>    plan  = list(string)<br/>    apply = list(string)<br/>  })</pre> | <pre>{<br/>  "apply": [],<br/>  "plan": []<br/>}</pre> | no |
| <a name="input_workload_service_accounts"></a> [workload\_service\_accounts](#input\_workload\_service\_accounts) | Map of environment key -> { plan, apply } SA emails (gcp-bootstrap output workload\_service\_accounts). Each pair is granted var.workload\_folder\_roles on its OWN environment folder (var.folders[<env>]). Default {} = no grants. | <pre>map(object({<br/>    plan  = string<br/>    apply = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_automation_folder_grants"></a> [automation\_folder\_grants](#output\_automation\_folder\_grants) | Folder IAM grants made to the workload / network-hub automation SAs, keyed "<env>\|<phase>\|<role>" (workload) and "network\|<phase>\|<role>". |
| <a name="output_project_ids"></a> [project\_ids](#output\_project\_ids) | Map of Project IDs |
| <a name="output_project_numbers"></a> [project\_numbers](#output\_project\_numbers) | Map of Project Numbers |
| <a name="output_projects"></a> [projects](#output\_projects) | Map of created projects, keyed "<env>-<project>": { id, project\_id, number, name, parent, labels, billing\_account }. |
<!-- END_TF_DOCS -->
