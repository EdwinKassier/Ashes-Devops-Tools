# Network Hub Stage Module

Establishes the centralized networking architecture (Hub-and-Spoke topology).

## Purpose

- Creates the **Shared VPC** in a dedicated hub project
- Configures **Cloud DNS** hub for centralized name resolution
- Sets up **VPC Service Controls** perimeters (dry-run initially)
- Implements **Hierarchical Firewall Policies**
- Manages **Interconnect/VPN** gateways (if configured)

## Architecture

This module creates two core projects:
1. `net-hub`: Hosts the Shared VPC code
2. `dns-hub`: Hosts private DNS zones

## Usage

```hcl
module "network_hub" {
  source = "../../modules/stages/network-hub"

  org_id          = "123456789"
  hub_project_id  = "my-org-net-hub"
  dns_project_id  = "my-org-dns-hub"
  
  # DNS Configuration
  internal_domain = "internal.mycompany.com"

  # Spoke Attachments
  spoke_project_ids = {
    "prod-app" = "project-123"
  }
}
```

## Security Features

- **Private Google Access**: Enforced on all subnets
- **VPC-SC**: Data exfiltration protection for sensitive services
- **Firewall**: Default deny ingress, strict egress

## Outputs

- `hub_vpc_self_link`: Self link of the hub VPC
- `hub_vpc_name`: Name of the hub VPC
- `dns_zone_name`: Name of the managed DNS zone
- `hub_dns_domain`: DNS name managed by the hub DNS project

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	default_region = 
	dns_project_id = 
	folders = 
	hub_project_id = 
	org_id = 
	project_prefix = 
	spoke_project_ids = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

No providers.

## Modules


- dns_hub_network - ../../host
- dns_hub_zone - ../../network/dns
- hub_network - ../../host


## Resources

The following resources are created:




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Default GCP region for resources | `string` | n/a | yes |
| <a name="input_dns_project_id"></a> [dns\_project\_id](#input\_dns\_project\_id) | Project ID for the DNS hub | `string` | n/a | yes |
| <a name="input_folders"></a> [folders](#input\_folders) | Map of folder objects to attach policies to | <pre>map(object({<br/>    id           = string<br/>    name         = string<br/>    display_name = string<br/>  }))</pre> | n/a | yes |
| <a name="input_hub_project_id"></a> [hub\_project\_id](#input\_hub\_project\_id) | Project ID for the network hub | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Organization ID (format: organizations/123456789) | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Prefix used for project naming | `string` | n/a | yes |
| <a name="input_spoke_project_ids"></a> [spoke\_project\_ids](#input\_spoke\_project\_ids) | Map of spoke project IDs to attach to Shared VPC | `map(string)` | n/a | yes |
| <a name="input_internal_domain"></a> [internal\_domain](#input\_internal\_domain) | Internal domain for private DNS zone (e.g., 'mycompany.com') | `string` | `"internal.local"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns_zone_name"></a> [dns\_zone\_name](#output\_dns\_zone\_name) | Name of the managed private DNS zone |
| <a name="output_hub_dns_domain"></a> [hub\_dns\_domain](#output\_hub\_dns\_domain) | DNS suffix served by the hub DNS project |
| <a name="output_hub_vpc_name"></a> [hub\_vpc\_name](#output\_hub\_vpc\_name) | Name of the hub VPC |
| <a name="output_hub_vpc_self_link"></a> [hub\_vpc\_self\_link](#output\_hub\_vpc\_self\_link) | Self link of the hub VPC |
<!-- END_TF_DOCS -->
