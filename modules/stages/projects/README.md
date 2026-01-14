# Projects Stage Module

> **Platform Infrastructure Projects Only**  
> This module creates **platform/infrastructure projects** (VPC hosts, network hubs, shared services).  
> For **application/workload projects**, use [`modules/stages/workload`](../workload/README.md) instead.

## Purpose

Creates foundational infrastructure projects at the **organization layer** for:
- **Host Projects**: VPC hosts for each environment (dev-host, uat-host, prod-host)
- **Shared Projects**: Network hub, DNS hub, logging sinks
- **Infrastructure Projects**: Any platform-managed projects defined in `var.environments`

## When to Use This vs Workload Factory

| Aspect | `stages/projects` (this) | `stages/workload` |
|--------|--------------------------|-------------------|
| **Owner** | Platform Team | Application Teams |
| **Lifecycle** | Created at org setup | Created on-demand |
| **Location** | `envs/organisation/` | `envs/{dev,uat,prod}/workloads.tf` |
| **Purpose** | Infrastructure backbone | Application deployments |
| **Examples** | `dev-host`, `shared-hub`, `dns-hub` | `dev-api`, `prod-payment` |

## How It Works

```
envs/organisation/main.tf
    │
    └── module "projects" (this module)
            │
            ├── dev-host     ─→ Used by envs/dev/main.tf
            ├── uat-host     ─→ Used by envs/uat/main.tf
            ├── prod-host    ─→ Used by envs/prod/main.tf
            ├── shared-hub   ─→ Network connectivity hub
            └── shared-dns   ─→ DNS resolution hub
```

## Usage

This module is invoked **once** in `envs/organisation/main.tf`:

```hcl
module "projects" {
  source = "../../modules/stages/projects"

  project_prefix          = var.project_prefix
  organization_name       = var.organization_name
  default_billing_account = data.google_billing_account.billing.id
  admin_project_id        = module.bootstrap.admin_project_id
  folders                 = module.organization.folders
  environments            = var.environments  # Defines all projects
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
