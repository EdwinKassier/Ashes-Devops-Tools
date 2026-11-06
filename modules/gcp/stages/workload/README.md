# Workload Factory Module

> **Application/Service Projects**
> This module creates **application workload projects** for teams and attaches them to Shared VPC.
> For **platform infrastructure projects** (hosts, hubs), use [`modules/gcp/stages/projects`](../projects/README.md) instead.

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
| **Location** | `examples/workloads/` | `envs/gcp/organization/` |
| **Purpose** | Application deployments | Infrastructure backbone |
| **Examples** | `api-service`, `payments-service` | `apps-host`, `shared-hub` |

## How It Works

```text
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
  source = "../../modules/gcp/stages/workload"

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

- **Project Creation**: Creates the project through the shared [project primitive](../../project/README.md) (`<project_name>-<4 hex>` ID, no default network, `deletion_policy = PREVENT`, APIs never disabled on destroy)
- **APIs**: `compute` + `servicenetworking` always; `container.googleapis.com` only when `enable_gke` (or `enable_gke_network_user`) is `true` — it is no longer force-enabled
- **Project SA / default SA**: creates `project-service-account` (`create_project_service_account`, default `true`) and disables the default compute SA (`default_service_account_action`, default `DISABLE`) — parity with the upstream project-factory defaults this stage used to call
- **Shared VPC**: Automatically attaches as service project to host
- **IAM Bindings**: Grants admin roles to specified Google Group
- **Network User**: Configures subnet-level access for workload service accounts
- **GKE Ready**: Optionally grants container engine robot subnet access (opt-in via `enable_gke_network_user`, default `false`)

## Inputs

| Variable | Description | Required |
|----------|-------------|:--------:|
| `project_name` | Display name and project-ID stem (4-25 chars) | Yes |
| `org_id` | Organization ID (parent when `folder_id` is null) | Yes |
| `folder_id` | Folder ID to create project in | No |
| `billing_account` | Billing account ID | Yes |
| `project_admin_group_email` | Google Group for project admins | Yes |
| `shared_vpc_host_project_id` | Host project for Shared VPC | No |
| `shared_vpc_subnets` | Subnets to grant access to | No |
| `activate_apis` | Additional APIs to enable | No |
| `enable_gke` | Enable `container.googleapis.com` | No |

## Outputs

| Output | Description |
|--------|-------------|
| `project_id` | The ID of the created project |
| `project_number` | The numeric project identifier |
| `service_account_email` | `project-service-account` email (null when not created) |

## Migrating state (from the upstream project-factory)

Earlier versions wrapped `terraform-google-modules/project-factory/google ~> 18.2`.
`moved.tf` maps every resource that call instantiated, so the first plan after
upgrading **replaces nothing**:

| Old address (inside this stage) | New address |
|---|---|
| `module.project.module.project-factory.google_project.main` | `module.project.google_project.this` |
| `module.project.module.project-factory.random_id.random_project_id_suffix` | `random_id.project_suffix` |
| `module.project.module.project-factory.google_service_account.default_service_account[0]` | `google_service_account.project[0]` |
| `module.project.module.project-factory.google_project_default_service_accounts.default_service_accounts[0]` | `google_project_default_service_accounts.this[0]` |
| `google_compute_shared_vpc_service_project.attachment[0]` | `module.project.google_compute_shared_vpc_service_project.this[0]` |
| `module.project.module.project-factory.module.project_services.google_project_service.project_services` | **forgotten** (`removed`, `destroy = false`) and re-adopted as `module.project.google_project_service.this` |

APIs are forgotten rather than moved because the upstream module set
`disable_on_destroy = true`: a move would carry that flag into the destroy of any
API no longer requested and disable it on a live project. Expect the first plan
to show the APIs as "will no longer be managed" plus "to add" (a no-op enable).

**GKE users:** `container.googleapis.com` is now opt-in. If a team project runs
GKE, set `enable_gke = true` (or `enable_gke_network_user = true`) on it; if you
do not, the API simply stays enabled but unmanaged — it is never disabled.

## See Also

- [Projects Module](../projects/README.md) - For platform infrastructure projects

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Workload Factory Module

This module implements the "Project Factory" pattern for service projects.
It standardizes the creation of workload projects, enabling APIs,
and attaching them to the Shared VPC Host.

The project itself is created by the shared project primitive
(modules/gcp/project) — the same module stages/bootstrap and stages/projects
use — instead of the upstream terraform-google-modules/project-factory
(audit Modularity-H). The stage keeps only what the upstream factory did for
this caller: a random 4-hex project-ID suffix, a dedicated
"project-service-account", and disabling the default compute SA.
container.googleapis.com is no longer force-enabled: set enable\_gke.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	billing_account =
	org_id =
	project_admin_group_email =
	project_name =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules


- project - ../../project


## Resources

The following resources are created:


- resource.google_compute_subnetwork_iam_member.network_users (modules/gcp/stages/workload/main.tf#L126)
- resource.google_project_default_service_accounts.this (modules/gcp/stages/workload/main.tf#L71)
- resource.google_project_iam_member.project_admins (modules/gcp/stages/workload/main.tf#L88)
- resource.google_service_account.project (modules/gcp/stages/workload/main.tf#L60)
- resource.random_id.project_suffix (modules/gcp/stages/workload/main.tf#L25)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | The GCP Billing Account ID in format XXXXXX-XXXXXX-XXXXXX | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The numeric GCP Organization ID (digits only, without 'organizations/' prefix). Used as the parent only when folder\_id is null. | `string` | n/a | yes |
| <a name="input_project_admin_group_email"></a> [project\_admin\_group\_email](#input\_project\_admin\_group\_email) | Email of the Google Group to grant admin access | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Display name of the project, also the project-ID stem: the project ID is "<project\_name>-<4 hex>". 4-25 chars, lowercase letters, digits and hyphens, starting with a letter. | `string` | n/a | yes |
| <a name="input_activate_apis"></a> [activate\_apis](#input\_activate\_apis) | Additional APIs to enable in the project. compute.googleapis.com and servicenetworking.googleapis.com are always enabled; container.googleapis.com only when enable\_gke (or enable\_gke\_network\_user) is true. | `list(string)` | `[]` | no |
| <a name="input_create_project_service_account"></a> [create\_project\_service\_account](#input\_create\_project\_service\_account) | Create the dedicated "project-service-account" SA in the project (and grant it compute.networkUser on the Shared VPC subnets). Matches the upstream project-factory default (create\_project\_sa = true). | `bool` | `true` | no |
| <a name="input_default_service_account_action"></a> [default\_service\_account\_action](#input\_default\_service\_account\_action) | What to do with the project's default compute service account: DISABLE (default, matches the upstream project-factory), DEPRIVILEGE, DELETE or KEEP (leave it untouched). | `string` | `"DISABLE"` | no |
| <a name="input_enable_gke"></a> [enable\_gke](#input\_enable\_gke) | Enable container.googleapis.com (GKE) on the project. Previously force-enabled on every workload project by the upstream project-factory call; now opt-in. Implied by enable\_gke\_network\_user. | `bool` | `false` | no |
| <a name="input_enable_gke_network_user"></a> [enable\_gke\_network\_user](#input\_enable\_gke\_network\_user) | When true, also grants the GKE robot service account<br/>(service-PROJECT\_NUMBER@container-engine-robot.iam.gserviceaccount.com)<br/>the roles/compute.networkUser role on the shared VPC subnets. Set to true<br/>only when this service project will use GKE — the GKE robot SA is created<br/>lazily when container.googleapis.com is first activated, so enabling this<br/>flag before GKE is enabled creates a dangling IAM binding that Terraform<br/>will attempt to reconcile on every apply. | `bool` | `false` | no |
| <a name="input_enable_shared_vpc_attachment"></a> [enable\_shared\_vpc\_attachment](#input\_enable\_shared\_vpc\_attachment) | Whether to attach this project to a Shared VPC Host | `bool` | `true` | no |
| <a name="input_folder_id"></a> [folder\_id](#input\_folder\_id) | The numeric Folder ID to create the project in (digits only, without 'folders/' prefix). When null the project is created directly under org\_id. | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the project | `map(string)` | `{}` | no |
| <a name="input_project_admin_roles"></a> [project\_admin\_roles](#input\_project\_admin\_roles) | List of roles to grant to the admin group at project level.<br/><br/>Bindings are managed via google\_project\_iam\_member (additive). Manually-granted<br/>bindings or bindings managed by other tools are preserved on every apply — this<br/>module will not evict them.<br/><br/>Validation blocks reject primitive roles (owner/editor/viewer) and<br/>cross-boundary privileged roles (organizationAdmin, folderAdmin, securityAdmin,<br/>organizationRoleAdmin, billing.admin, billing.creator). Use least-privilege<br/>predefined or custom roles only. | `list(string)` | `[]` | no |
| <a name="input_shared_vpc_host_project_id"></a> [shared\_vpc\_host\_project\_id](#input\_shared\_vpc\_host\_project\_id) | The Host Project ID for Shared VPC | `string` | `""` | no |
| <a name="input_shared_vpc_subnets"></a> [shared\_vpc\_subnets](#input\_shared\_vpc\_subnets) | Map of subnet key to subnet configuration in the Shared VPC Host Project. Must not be empty when enable\_shared\_vpc\_attachment is true — at least one subnet must be granted to allow workloads to use the shared network. | <pre>map(object({<br/>    region      = string<br/>    subnet_name = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_host_project_id"></a> [host\_project\_id](#output\_host\_project\_id) | The Shared VPC host project ID this service project is attached to (null if Shared VPC attachment is disabled) |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | The ID of the created project |
| <a name="output_project_number"></a> [project\_number](#output\_project\_number) | The numeric identifier of the created project |
| <a name="output_service_account_email"></a> [service\_account\_email](#output\_service\_account\_email) | The email of the dedicated project service account (project-service-account@...); null when create\_project\_service\_account = false |
| <a name="output_subnet_iam_bindings"></a> [subnet\_iam\_bindings](#output\_subnet\_iam\_bindings) | Map of (subnet\_key/member\_type) to IAM member resource ID for the networkUser bindings granted to this service project |
<!-- END_TF_DOCS -->
