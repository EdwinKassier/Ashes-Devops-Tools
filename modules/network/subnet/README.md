# Subnet Module

This module is a reusable factory for creating Google Compute Subnetworks with standardized logging and configuration.

## Features

- **Standardization**: Enforces consistent naming and configuration.
- **Flow Logs**: Configurable VPC Flow Logs aggregation and sampling.
- **Secondary Ranges**: Supports adding secondary IP ranges (e.g., for GKE).
- **Private Access**: Toggles Private Google Access.

## Usage

```hcl
module "app_subnet" {
  source = "./modules/network/subnet"

  project_id    = "my-project-id"
  region        = "us-central1"
  network       = "projects/my-project/global/networks/my-vpc"
  subnet_name   = "my-subnet"
  ip_cidr_range = "10.0.1.0/24"

  enable_flow_logs                = true
  log_config_aggregation_interval = "INTERVAL_5_SEC"
  log_config_flow_sampling        = 0.5
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `region` | GCP Region | `string` | n/a | yes |
| `network` | VPC network self-link | `string` | n/a | yes |
| `subnet_name` | Name of the subnet | `string` | n/a | yes |
| `ip_cidr_range` | Primary CIDR range | `string` | n/a | yes |
| `description` | Description of the subnet | `string` | `null` | no |
| `secondary_ip_ranges` | List of secondary ranges | `list(object)` | `[]` | no |
| `private_ip_google_access` | Enable Private Google Access | `bool` | `true` | no |
| `enable_flow_logs` | Enable VPC Flow Logs | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `subnet` | The full subnet resource |
| `id` | The subnet ID |
| `self_link` | The subnet URI |
| `ip_cidr_range` | The primary CIDR range |
