# Shared VPC Service Project Module

This module attaches a service project to a Shared VPC host project and configures the necessary IAM permissions for network access.

## Features

- **Service Project Attachment**: Attach service projects to a Shared VPC host
- **Subnet-Level IAM**: Grant network access to specific subnets only
- **Project-Level IAM**: Grant network access to all subnets
- **GKE Permissions**: Configure permissions for GKE clusters in service projects

## Prerequisites

The host project must already be configured as a Shared VPC Host Project. You can use the `vpc` module with `enable_shared_vpc_host = true` for this.

## Usage

### Basic Service Project Attachment

```hcl
module "shared_vpc_service" {
  source = "../shared-vpc-service"

  host_project_id    = "host-project-id"
  service_project_id = "service-project-id"
}
```

### With Subnet-Level IAM

```hcl
module "shared_vpc_service" {
  source = "../shared-vpc-service"

  host_project_id    = "host-project-id"
  service_project_id = "service-project-id"

  # Grant specific service accounts access to specific subnets
  subnet_iam_bindings = [
    {
      subnet = "private-subnet-us-central1-a"
      region = "us-central1"
      member = "serviceAccount:my-service@service-project-id.iam.gserviceaccount.com"
    },
    {
      subnet = "private-subnet-us-central1-b"
      region = "us-central1"
      member = "serviceAccount:my-service@service-project-id.iam.gserviceaccount.com"
    }
  ]
}
```

### With Project-Level Network Access

```hcl
module "shared_vpc_service" {
  source = "../shared-vpc-service"

  host_project_id    = "host-project-id"
  service_project_id = "service-project-id"

  # Grant access to all subnets
  grant_network_user_to_all_subnets = true
  network_user_members = [
    "serviceAccount:my-service@service-project-id.iam.gserviceaccount.com",
    "serviceAccount:another-service@service-project-id.iam.gserviceaccount.com"
  ]

  # Grant read-only access
  network_viewer_members = [
    "group:developers@example.com"
  ]
}
```

### With GKE Cluster Support

```hcl
module "shared_vpc_service" {
  source = "../shared-vpc-service"

  host_project_id    = "host-project-id"
  service_project_id = "service-project-id"

  # Enable GKE service account permissions
  enable_gke_permissions = true

  # Grant network access
  grant_network_user_to_all_subnets = true
  network_user_members = [
    "serviceAccount:service-PROJECT_NUMBER@container-engine-robot.iam.gserviceaccount.com"
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| host_project_id | The ID of the Shared VPC Host Project | `string` | n/a | yes |
| service_project_id | The ID of the Service Project to attach | `string` | n/a | yes |
| deletion_policy | The deletion policy for the shared VPC link | `string` | `"ABANDON"` | no |
| subnet_iam_bindings | List of subnet-level IAM bindings | `list(object)` | `[]` | no |
| grant_network_user_to_all_subnets | Grant compute.networkUser at project level | `bool` | `false` | no |
| network_user_members | Members to grant compute.networkUser role | `list(string)` | `[]` | no |
| network_viewer_members | Members to grant compute.networkViewer role | `list(string)` | `[]` | no |
| enable_gke_permissions | Grant GKE service account permissions | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the shared VPC service project attachment |
| self_link | The ID of the shared VPC service project attachment |
| host_project_id | The host project ID |
| service_project_id | The service project ID |
| service_project_number | The service project number |

## IAM Roles Reference

| Role | Description |
|------|-------------|
| `roles/compute.networkUser` | Allows using VPC networks and subnets |
| `roles/compute.networkViewer` | Read-only access to networking resources |
| `roles/container.hostServiceAgentUser` | Required for GKE clusters in service projects |

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Shared VPC Service Project Module - Main Configuration

Attaches a service project to a Shared VPC host project and optionally
grants subnet-level IAM permissions to service accounts.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	host_project_id = 
	service_project_id = 
	
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


- resource.google_compute_shared_vpc_service_project.service_project (modules/network/shared-vpc-service/main.tf#L14)
- resource.google_compute_subnetwork_iam_member.subnet_users (modules/network/shared-vpc-service/main.tf#L26)
- resource.google_project_iam_member.gke_host_service_agent (modules/network/shared-vpc-service/main.tf#L63)
- resource.google_project_iam_member.network_users (modules/network/shared-vpc-service/main.tf#L41)
- resource.google_project_iam_member.network_viewers (modules/network/shared-vpc-service/main.tf#L50)
- data source.google_project.service_project (modules/network/shared-vpc-service/main.tf#L74)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_host_project_id"></a> [host\_project\_id](#input\_host\_project\_id) | The ID of the Shared VPC Host Project | `string` | n/a | yes |
| <a name="input_service_project_id"></a> [service\_project\_id](#input\_service\_project\_id) | The ID of the Service Project to attach | `string` | n/a | yes |
| <a name="input_deletion_policy"></a> [deletion\_policy](#input\_deletion\_policy) | The deletion policy for the shared VPC link. ABANDON to leave resources, DELETE to destroy them. | `string` | `"ABANDON"` | no |
| <a name="input_enable_gke_permissions"></a> [enable\_gke\_permissions](#input\_enable\_gke\_permissions) | Whether to grant GKE service account permissions on host project | `bool` | `false` | no |
| <a name="input_grant_network_user_to_all_subnets"></a> [grant\_network\_user\_to\_all\_subnets](#input\_grant\_network\_user\_to\_all\_subnets) | Whether to grant compute.networkUser at project level (access to all subnets) | `bool` | `false` | no |
| <a name="input_network_user_members"></a> [network\_user\_members](#input\_network\_user\_members) | List of members to grant compute.networkUser role (when grant\_network\_user\_to\_all\_subnets is true) | `list(string)` | `[]` | no |
| <a name="input_network_viewer_members"></a> [network\_viewer\_members](#input\_network\_viewer\_members) | List of members to grant compute.networkViewer role (read-only network access) | `list(string)` | `[]` | no |
| <a name="input_subnet_iam_bindings"></a> [subnet\_iam\_bindings](#input\_subnet\_iam\_bindings) | List of subnet-level IAM bindings for compute.networkUser role | <pre>list(object({<br/>    subnet = string<br/>    region = string<br/>    member = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_host_project_id"></a> [host\_project\_id](#output\_host\_project\_id) | The host project ID |
| <a name="output_id"></a> [id](#output\_id) | The ID of the shared VPC service project attachment |
| <a name="output_network_user_members"></a> [network\_user\_members](#output\_network\_user\_members) | The project-level network user IAM members |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The ID of the shared VPC service project attachment |
| <a name="output_service_project"></a> [service\_project](#output\_service\_project) | The shared VPC service project attachment resource |
| <a name="output_service_project_id"></a> [service\_project\_id](#output\_service\_project\_id) | The service project ID |
| <a name="output_service_project_number"></a> [service\_project\_number](#output\_service\_project\_number) | The service project number |
| <a name="output_subnet_iam_members"></a> [subnet\_iam\_members](#output\_subnet\_iam\_members) | The subnet IAM member bindings |
<!-- END_TF_DOCS -->