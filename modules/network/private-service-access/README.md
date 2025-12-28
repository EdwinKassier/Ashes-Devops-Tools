# Private Service Access Module

This module configures **Private Service Access** (PSA), which allows your VPC to peer with Google's Service Networking API. This is required for managed services like **Cloud SQL**, **Cloud Memorystore** (Redis), and **Vertex AI**.

## Features

- **Global Allocation**: Reserves a global internal IP range (CIDR) for managed services.
- **Peering**: Creates the peering connection to `servicenetworking.googleapis.com`.
- **IP Management**: Prevents IP overlap by allocating a specific prefix.

## Usage

```hcl
module "psa_sql" {
  source = "./modules/network/private-service-access"

  project_id    = "my-project-id"
  vpc_network   = "projects/my-project/global/networks/my-vpc"
  name          = "google-services-range"
  prefix_length = 16
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `vpc_network` | VPC network self-link | `string` | n/a | yes |
| `name` | Name of the IP allocation | `string` | `...` | no |
| `prefix_length` | CIDR prefix length (e.g. 16, 24) | `number` | `16` | no |
| `address` | Specific starting IP | `string` | `null` | no |
| `service` | Service to peer with | `string` | `"servicenetworking..."` | no |

## Outputs

| Name | Description |
|------|-------------|
| `address` | The reserved IP range |
| `peering` | The peering connection resource |
