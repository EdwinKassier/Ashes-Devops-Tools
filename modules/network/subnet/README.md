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

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Subnet Module - Main Configuration

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	ip_cidr_range = 
	network = 
	project_id = 
	region = 
	subnet_name = 
	
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
| <a name="provider_google"></a> [google](#provider\_google) | 7.14.1 |



## Resources

The following resources are created:


- resource.google_compute_subnetwork.subnet (modules/network/subnet/main.tf#L7)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ip_cidr_range"></a> [ip\_cidr\_range](#input\_ip\_cidr\_range) | The range of internal addresses for this subnet | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The VPC network ID to attach this subnet to | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where the subnet will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where the subnet will be created | `string` | n/a | yes |
| <a name="input_subnet_name"></a> [subnet\_name](#input\_subnet\_name) | Name of the subnet | `string` | n/a | yes |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Whether to enable VPC flow logs for this subnet | `bool` | `true` | no |
| <a name="input_log_config_aggregation_interval"></a> [log\_config\_aggregation\_interval](#input\_log\_config\_aggregation\_interval) | Aggregation interval for collecting flow logs | `string` | `"INTERVAL_5_SEC"` | no |
| <a name="input_log_config_flow_sampling"></a> [log\_config\_flow\_sampling](#input\_log\_config\_flow\_sampling) | Sampling rate for VPC flow logs (0.0 to 1.0) | `number` | `0.5` | no |
| <a name="input_log_config_metadata"></a> [log\_config\_metadata](#input\_log\_config\_metadata) | Metadata to include in flow logs | `string` | `"INCLUDE_ALL_METADATA"` | no |
| <a name="input_private_ip_google_access"></a> [private\_ip\_google\_access](#input\_private\_ip\_google\_access) | When enabled, VMs in this subnet can access Google APIs and services without external IPs | `bool` | `true` | no |
| <a name="input_purpose"></a> [purpose](#input\_purpose) | Purpose of the subnet (PRIVATE, REGIONAL\_MANAGED\_PROXY, etc.) | `string` | `null` | no |
| <a name="input_role"></a> [role](#input\_role) | Role for the subnet when purpose is set (ACTIVE or BACKUP) | `string` | `null` | no |
| <a name="input_secondary_ip_ranges"></a> [secondary\_ip\_ranges](#input\_secondary\_ip\_ranges) | Secondary IP ranges for the subnet (useful for GKE pods/services) | <pre>list(object({<br/>    range_name    = string<br/>    ip_cidr_range = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_gateway_address"></a> [gateway\_address](#output\_gateway\_address) | The gateway address for default routing out of the subnet |
| <a name="output_id"></a> [id](#output\_id) | The ID of the subnet |
| <a name="output_ip_cidr_range"></a> [ip\_cidr\_range](#output\_ip\_cidr\_range) | The IP CIDR range of the subnet |
| <a name="output_name"></a> [name](#output\_name) | The name of the subnet |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The URI of the subnet |
| <a name="output_subnet"></a> [subnet](#output\_subnet) | The created subnet resource |
<!-- END_TF_DOCS -->