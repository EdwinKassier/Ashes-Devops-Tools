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

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

VPC Module - Main Configuration

This module creates a Google Cloud VPC network and optionally configures it as
a Shared VPC Host project. It is a foundational module that should be composed
with other modules (subnets, firewalls, etc.) to build a complete network.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id = 
	
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
| <a name="provider_google"></a> [google](#provider\_google) | 6.50.0 |



## Resources

The following resources are created:


- resource.google_compute_network.vpc (modules/network/vpc/main.tf#L12)
- resource.google_compute_shared_vpc_host_project.host (modules/network/vpc/main.tf#L28)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where this VPC will be created | `string` | n/a | yes |
| <a name="input_auto_create_subnetworks"></a> [auto\_create\_subnetworks](#input\_auto\_create\_subnetworks) | When set to true, the network is created in 'auto subnet mode' and it will create a subnet for each region automatically | `bool` | `false` | no |
| <a name="input_delete_default_routes_on_create"></a> [delete\_default\_routes\_on\_create](#input\_delete\_default\_routes\_on\_create) | If set to true, default routes (0.0.0.0/0) will be deleted immediately after network creation | `bool` | `true` | no |
| <a name="input_description"></a> [description](#input\_description) | An optional description of this resource | `string` | `"Managed by Terraform"` | no |
| <a name="input_enable_shared_vpc_host"></a> [enable\_shared\_vpc\_host](#input\_enable\_shared\_vpc\_host) | Enable this project as a Shared VPC Host Project | `bool` | `false` | no |
| <a name="input_routing_mode"></a> [routing\_mode](#input\_routing\_mode) | The network routing mode (default 'GLOBAL') | `string` | `"GLOBAL"` | no |
| <a name="input_vpc_name"></a> [vpc\_name](#input\_vpc\_name) | The name of the VPC network | `string` | `"main-vpc"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | The ID of the VPC |
| <a name="output_name"></a> [name](#output\_name) | The name of the VPC |
| <a name="output_network"></a> [network](#output\_network) | The created VPC resource |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | Deprecated alias for the VPC ID |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Deprecated alias for the VPC name |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | Deprecated alias for the VPC self link |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The URI of the VPC |
<!-- END_TF_DOCS -->