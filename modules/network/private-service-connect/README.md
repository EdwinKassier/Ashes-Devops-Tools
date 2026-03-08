# Private Service Connect Module

This module creates a Private Service Connect (PSC) endpoint to access Google APIs securely from within your VPC, without using public IP addresses.

## Features

- **Secure Access**: Access APIs like Storage, BigQuery, and more over private IP.
- **DNS Integration**: automatically creates a private DNS zone for `googleapis.com` pointing to the endpoint.
- **Global Access**: Reserves a global internal IP address.

## Usage

```hcl
module "psc_apis" {
  source = "./modules/network/private-service-connect"

  project_id = "my-project-id"
  name       = "psc-googleapis"
  network    = "projects/my-project/global/networks/my-vpc"
  target     = "all-apis"  # or "vpc-sc"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `name` | Name of the PSC endpoint | `string` | n/a | yes |
| `network` | VPC network self-link | `string` | n/a | yes |
| `target` | Target bundle (`all-apis`, `vpc-sc`) | `string` | `"all-apis"` | no |
| `address` | Specific IP to reserve | `string` | `null` | no |
| `create_dns_zone` | Create split-horizon DNS zone | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `address` | The reserved global internal IP |
| `forwarding_rule` | The PSC forwarding rule |
| `dns_zone` | The private DNS zone resource |

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Private Service Connect Module - Main Configuration

Creates a Private Service Connect endpoint for accessing Google APIs
without using public IP addresses.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	name = 
	network = 
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
| <a name="provider_google"></a> [google](#provider\_google) | 7.14.1 |



## Resources

The following resources are created:


- resource.google_compute_global_address.psc_address (modules/network/private-service-connect/main.tf#L23)
- resource.google_compute_global_forwarding_rule.psc_forwarding_rule (modules/network/private-service-connect/main.tf#L36)
- resource.google_dns_managed_zone.psc_dns (modules/network/private-service-connect/main.tf#L50)
- resource.google_dns_record_set.psc_googleapis (modules/network/private-service-connect/main.tf#L68)
- resource.google_dns_record_set.psc_googleapis_base (modules/network/private-service-connect/main.tf#L80)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Name of the Private Service Connect endpoint | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The self-link of the VPC network for the PSC endpoint | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The project ID where the PSC endpoint will be created | `string` | n/a | yes |
| <a name="input_address"></a> [address](#input\_address) | Specific IP address to reserve (optional, auto-assigned if not specified) | `string` | `null` | no |
| <a name="input_address_name"></a> [address\_name](#input\_address\_name) | Name of the internal IP address to reserve | `string` | `null` | no |
| <a name="input_create_dns_zone"></a> [create\_dns\_zone](#input\_create\_dns\_zone) | Create a private DNS zone for the PSC endpoint | `bool` | `true` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the PSC endpoint | `string` | `"Private Service Connect endpoint managed by Terraform"` | no |
| <a name="input_dns_zone_name"></a> [dns\_zone\_name](#input\_dns\_zone\_name) | Name of the private DNS zone for PSC | `string` | `"psc-googleapis"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the PSC resources | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | Region for the PSC endpoint (required for regional endpoints) | `string` | `null` | no |
| <a name="input_subnetwork"></a> [subnetwork](#input\_subnetwork) | The self-link of the subnetwork for the PSC endpoint (optional) | `string` | `null` | no |
| <a name="input_target"></a> [target](#input\_target) | The target service to connect to (e.g., 'all-apis', 'vpc-sc', or a service attachment URI) | `string` | `"all-apis"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_address"></a> [address](#output\_address) | The reserved IP address for the PSC endpoint |
| <a name="output_address_id"></a> [address\_id](#output\_address\_id) | The ID of the reserved IP address |
| <a name="output_dns_zone"></a> [dns\_zone](#output\_dns\_zone) | The private DNS zone for PSC (if created) |
| <a name="output_forwarding_rule"></a> [forwarding\_rule](#output\_forwarding\_rule) | The PSC forwarding rule resource |
| <a name="output_id"></a> [id](#output\_id) | The ID of the PSC forwarding rule |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The URI of the PSC forwarding rule |
<!-- END_TF_DOCS -->