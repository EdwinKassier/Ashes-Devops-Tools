# Projects Stage Module

> **Platform Infrastructure Projects Only**  
> This module creates **platform/infrastructure projects** (VPC hosts, network hubs, shared services).  
> For **application/workload projects**, use [`modules/stages/workload`](../workload/README.md) instead.

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
| **Location** | `envs/organization/` | `examples/workloads/` |
| **Purpose** | Infrastructure backbone | Application deployments |
| **Examples** | `apps-host`, `shared-hub`, `dns-hub` | `api-service`, `payments-service` |

## How It Works

```
envs/organization/main.tf
    │
    └── module "projects" (this module)
            │
            ├── <env>-host   ─→ Used by envs/apps (apps-<env>)
            ├── shared-hub   ─→ Network connectivity hub
            └── shared-dns   ─→ DNS resolution hub
```

## Usage

This module is invoked **once** in `envs/organization/main.tf`:

```hcl
module "projects" {
  source = "../../modules/stages/projects"

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |



## Resources

The following resources are created:


- resource.google_monitoring_monitored_project.projects (modules/stages/projects/main.tf#L68)
- resource.google_project.projects (modules/stages/projects/main.tf#L12)
- resource.google_project_service.project_services (modules/stages/projects/main.tf#L55)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_project_id"></a> [admin\_project\_id](#input\_admin\_project\_id) | n/a | `string` | n/a | yes |
| <a name="input_default_billing_account"></a> [default\_billing\_account](#input\_default\_billing\_account) | n/a | `string` | n/a | yes |
| <a name="input_environments"></a> [environments](#input\_environments) | Map of environment definitions | <pre>map(object({<br/>    display_name = string<br/>    description  = string<br/>    projects = map(object({<br/>      name            = string<br/>      billing_account = optional(string)<br/>      labels          = map(string)<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_folders"></a> [folders](#input\_folders) | n/a | <pre>map(object({<br/>    id           = string<br/>    name         = string<br/>    display_name = string<br/>  }))</pre> | n/a | yes |
| <a name="input_organization_name"></a> [organization\_name](#input\_organization\_name) | n/a | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | n/a | `string` | n/a | yes |
| <a name="input_suffix"></a> [suffix](#input\_suffix) | Random suffix from bootstrap module | `string` | n/a | yes |
| <a name="input_project_services"></a> [project\_services](#input\_project\_services) | n/a | `list(string)` | <pre>[<br/>  "cloudresourcemanager.googleapis.com",<br/>  "compute.googleapis.com",<br/>  "serviceusage.googleapis.com",<br/>  "iam.googleapis.com",<br/>  "cloudbilling.googleapis.com",<br/>  "monitoring.googleapis.com"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_project_ids"></a> [project\_ids](#output\_project\_ids) | Map of Project IDs |
| <a name="output_project_numbers"></a> [project\_numbers](#output\_project\_numbers) | Map of Project Numbers |
| <a name="output_projects"></a> [projects](#output\_projects) | Map of created projects |
<!-- END_TF_DOCS -->