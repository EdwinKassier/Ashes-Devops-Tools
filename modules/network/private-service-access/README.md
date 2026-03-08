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

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Private Service Access Module - Main Configuration

Reserves a Global Internal IP range and peers it with Google Service Networking
for access to managed services like Cloud SQL, Memorystore, etc.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id = 
	vpc_network = 
	
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


- resource.google_compute_global_address.private_ip_alloc (modules/network/private-service-access/main.tf#L11)
- resource.google_service_networking_connection.private_service_access (modules/network/private-service-access/main.tf#L24)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The project ID where the address and peering will be created | `string` | n/a | yes |
| <a name="input_vpc_network"></a> [vpc\_network](#input\_vpc\_network) | The self-link of the VPC network to peer with Google Services | `string` | n/a | yes |
| <a name="input_address"></a> [address](#input\_address) | The IP address (or starting address) to reserve (optional, auto-assigned if not specified) | `string` | `null` | no |
| <a name="input_description"></a> [description](#input\_description) | Description for the allocated IP range | `string` | `"Allocated IP range for Google Private Service Access"` | no |
| <a name="input_ip_version"></a> [ip\_version](#input\_ip\_version) | The IP version (IPV4 or IPV6) | `string` | `"IPV4"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the allocated address | `map(string)` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the allocated IP range | `string` | `"google-managed-services-ip-range"` | no |
| <a name="input_prefix_length"></a> [prefix\_length](#input\_prefix\_length) | The prefix length of the IP range (e.g., 16 for /16) | `number` | `16` | no |
| <a name="input_service"></a> [service](#input\_service) | The service to peer with (default is servicenetworking.googleapis.com) | `string` | `"servicenetworking.googleapis.com"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_address"></a> [address](#output\_address) | The allocated IP address/range |
| <a name="output_address_resource"></a> [address\_resource](#output\_address\_resource) | The reserved global IP address resource |
| <a name="output_id"></a> [id](#output\_id) | The ID of the service networking connection |
| <a name="output_peering"></a> [peering](#output\_peering) | The service networking connection resource |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The self\_link of the reserved global IP address |
<!-- END_TF_DOCS -->