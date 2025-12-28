# VPC Module

The central networking module for the Enterprise Boilerplate. It creates a robust Virtual Private Cloud (VPC) with auto-discovered availability zones, dynamic subnet allocation, and integrated security features.

## Features

- **Dynamic CIDR Allocation**: Automatically calculates unique `/16` CIDR blocks based on the region to avoid overlaps in multi-region setups.
- **Auto-Zone Discovery**: Automatically detects available zones in the region for subnet placement.
- **Tiered Subnets**: Creates Public, Private (Compute), and Database subnets in each zone.
- **Security**: Includes tiered firewall rules, database egress denial, IAP access, and NAT logging.
- **Integrated Services**: Optional built-in support for Private Service Access (Cloud SQL) and Private Service Connect (Google APIs).

## Usage

```hcl
module "vpc" {
  source = "./modules/network/vpc"

  project_id = "my-project-id"
  vpc_name   = "prod-vpc"
  region     = "us-central1"

  # Ops
  log_config_aggregation_interval = "INTERVAL_5_SEC"
  log_config_flow_sampling        = 0.5

  # Integrations
  enable_private_service_access  = true
  enable_private_service_connect = true
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `vpc_name` | Name of the VPC | `string` | `"three-tier-vpc"` | no |
| `region` | GCP Region | `string` | `"us-central1"` | no |
| `routing_mode` | Global or Regional routing | `string` | `"GLOBAL"` | no |
| `enable_private_service_access` | Enable Cloud SQL/Redis access | `bool` | `false` | no |
| `enable_private_service_connect`| Enable Google API access | `bool` | `false` | no |
| `enable_iap_access` | Allow IAP SSH/RDP | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `network` | The VPC network resource |
| `network_name` | The VPC name |
| `network_id` | The VPC ID |
| `network_self_link` | The VPC URI |
| `public_subnets` | Map of public subnet resources |
| `private_subnets` | Map of private subnet resources |
| `database_subnets` | Map of database subnet resources |
| `vpc_cidr_block` | The dynamically allocated CIDR block |
