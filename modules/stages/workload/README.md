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
| **Location** | `examples/workloads/` | `envs/organization/` |
| **Purpose** | Application deployments | Infrastructure backbone |
| **Examples** | `api-service`, `payments-service` | `apps-host`, `shared-hub` |

## How It Works

```
examples/workloads/service-project.tf
    │
    └── module "workload_api_service" (this module)
            │
            ├── Creates: my-org-api-service-abc123
            ├── Attaches to: <env>-host (Shared VPC)
            ├── IAM: Grants roles to team group
            └── Network: grants compute.networkUser on subnets
```

## Usage

Add workload projects in a dedicated workload root using the example under `examples/workloads/`:

```hcl
module "workload_api_service" {
  source = "../../modules/stages/workload"

  project_name = "${var.project_prefix}-${var.environment}-api"

  # Organization Context
  org_id          = data.terraform_remote_state.organization.outputs.org_id
  folder_id       = data.terraform_remote_state.organization.outputs.environment_config[var.environment].folder_id
  billing_account = data.terraform_remote_state.organization.outputs.billing_account

  # Team Access
  project_admin_group_email = "api-team@example.com"

  # Shared VPC Attachment
  enable_shared_vpc_attachment = true
  shared_vpc_host_project_id   = data.terraform_remote_state.organization.outputs.environment_config[var.environment].host_project_id

  # Subnet Access
  shared_vpc_subnets = {
    private = {
      region      = data.terraform_remote_state.organization.outputs.environment_config[var.environment].region
      subnet_name = "replace-with-private-subnet-name"
    }
  }

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

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Workload Factory Module

This module implements the "Project Factory" pattern for service projects.
It standardizes the creation of workload projects, enabling APIs,
and attaching them to the Shared VPC Host.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	billing_account = 
	folder_id = 
	org_id = 
	project_admin_group_email = 
	project_name = 
	
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

## Modules


- project - terraform-google-modules/project-factory/google (~> 14.0)


## Resources

The following resources are created:


- resource.google_compute_shared_vpc_service_project.attachment (modules/stages/workload/main.tf#L39)
- resource.google_compute_subnetwork_iam_binding.network_users (modules/stages/workload/main.tf#L64)
- resource.google_project_iam_binding.project_admins (modules/stages/workload/main.tf#L51)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | The Billing Account ID | `string` | n/a | yes |
| <a name="input_folder_id"></a> [folder\_id](#input\_folder\_id) | The Folder ID to create the project in | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The Organization ID | `string` | n/a | yes |
| <a name="input_project_admin_group_email"></a> [project\_admin\_group\_email](#input\_project\_admin\_group\_email) | Email of the Google Group to grant admin access | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | The name of the project to create | `string` | n/a | yes |
| <a name="input_activate_apis"></a> [activate\_apis](#input\_activate\_apis) | List of APIs to enable in the project | `list(string)` | `[]` | no |
| <a name="input_enable_shared_vpc_attachment"></a> [enable\_shared\_vpc\_attachment](#input\_enable\_shared\_vpc\_attachment) | Whether to attach this project to a Shared VPC Host | `bool` | `true` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the project | `map(string)` | `{}` | no |
| <a name="input_project_admin_roles"></a> [project\_admin\_roles](#input\_project\_admin\_roles) | List of roles to grant to the admin group | `list(string)` | `[]` | no |
| <a name="input_shared_vpc_host_project_id"></a> [shared\_vpc\_host\_project\_id](#input\_shared\_vpc\_host\_project\_id) | The Host Project ID for Shared VPC | `string` | `""` | no |
| <a name="input_shared_vpc_subnets"></a> [shared\_vpc\_subnets](#input\_shared\_vpc\_subnets) | List of subnets in the Host Project to grant access to | <pre>map(object({<br/>    region      = string<br/>    subnet_name = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | The ID of the created project |
| <a name="output_project_number"></a> [project\_number](#output\_project\_number) | The numeric identifier of the created project |
| <a name="output_service_account_email"></a> [service\_account\_email](#output\_service\_account\_email) | The email of the default service account |
<!-- END_TF_DOCS -->
