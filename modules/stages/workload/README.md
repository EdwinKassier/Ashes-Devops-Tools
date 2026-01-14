# Workload Factory Module

> **Application/Service Projects**  
> This module creates **application workload projects** for teams and attaches them to Shared VPC.  
> For **platform infrastructure projects** (hosts, hubs), use [`modules/stages/projects`](../projects/README.md) instead.

## Purpose

Implements the **Project Factory** pattern for self-service provisioning of application projects:
- Creates new service projects with standardized configuration
- Attaches to Shared VPC host for network connectivity
- Grants IAM permissions to application teams
- Enables required APIs automatically

## When to Use This vs Projects Module

| Aspect | `stages/workload` (this) | `stages/projects` |
|--------|--------------------------|-------------------|
| **Owner** | Application Teams | Platform Team |
| **Lifecycle** | Created on-demand | Created at org setup |
| **Location** | `envs/{dev,uat,prod}/workloads.tf` | `envs/organisation/` |
| **Purpose** | Application deployments | Infrastructure backbone |
| **Examples** | `dev-api`, `prod-payment` | `dev-host`, `shared-hub` |

## How It Works

```
envs/dev/workloads.tf
    │
    └── module "workload_api_service" (this module)
            │
            ├── Creates: my-org-dev-api-abc123
            ├── Attaches to: dev-host (Shared VPC)
            ├── IAM: Grants roles to team group
            └── Network: grants compute.networkUser on subnets
```

## Usage

Add workload projects in `envs/{env}/workloads.tf`:

```hcl
module "workload_api_service" {
  source = "../../modules/stages/workload"

  project_name = "${var.project_prefix}-dev-api"

  # Organization Context
  org_id          = data.terraform_remote_state.organization.outputs.org_id
  folder_id       = local.dev_config.folder_id
  billing_account = data.terraform_remote_state.organization.outputs.billing_account

  # Team Access
  project_admin_group_email = "api-team@example.com"

  # Shared VPC Attachment
  enable_shared_vpc_attachment = true
  shared_vpc_host_project_id   = local.dev_host_project_id

  # Subnet Access
  shared_vpc_subnets = [
    {
      region      = local.dev_config.region
      subnet_name = module.host.subnets["private"]["us-central1-a"].name
    }
  ]

  labels = {
    environment = var.environment
    team        = "api"
    app         = "api-service"
  }
}
```

## Features

- **Project Creation**: Creates project with random ID suffix (collision prevention)
- **Shared VPC**: Automatically attaches as service project to host
- **IAM Bindings**: Grants admin roles to specified Google Group
- **Network User**: Configures subnet-level access for workload service accounts
- **GKE Ready**: Grants container engine robot permissions

## Inputs

| Variable | Description | Required |
|----------|-------------|:--------:|
| `project_name` | Name of the project | Yes |
| `org_id` | Organization ID | Yes |
| `folder_id` | Folder ID to create project in | Yes |
| `billing_account` | Billing account ID | Yes |
| `project_admin_group_email` | Google Group for project admins | Yes |
| `shared_vpc_host_project_id` | Host project for Shared VPC | Yes |
| `shared_vpc_subnets` | Subnets to grant access to | No |
| `activate_apis` | Additional APIs to enable | No |

## Outputs

| Output | Description |
|--------|-------------|
| `project_id` | The ID of the created project |
| `project_number` | The numeric project identifier |
| `service_account_email` | Default service account email |

## See Also

- [Projects Module](../projects/README.md) - For platform infrastructure projects
