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
