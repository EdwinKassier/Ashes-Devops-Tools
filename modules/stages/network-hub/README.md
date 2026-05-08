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
	dns_hub_vpc_cidr_block = 
	dns_project_id = 
	folders = 
	hub_project_id = 
	hub_vpc_cidr_block = 
	org_id = 
	project_prefix = 
	spoke_project_ids = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 8.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | >= 6.0, < 8.0 |



## Modules


- dns_hub_network - ../../host
- dns_hub_zone - ../../network/dns
- hub_network - ../../host




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Default GCP region for resources | `string` | n/a | yes |
| <a name="input_dns_hub_vpc_cidr_block"></a> [dns\_hub\_vpc\_cidr\_block](#input\_dns\_hub\_vpc\_cidr\_block) | CIDR block for the DNS hub VPC (e.g. "10.1.0.0/16"). Required — must not overlap with hub\_vpc\_cidr\_block. | `string` | n/a | yes |
| <a name="input_dns_project_id"></a> [dns\_project\_id](#input\_dns\_project\_id) | Project ID for the DNS hub | `string` | n/a | yes |
| <a name="input_folders"></a> [folders](#input\_folders) | Map of folder objects to attach policies to | <pre>map(object({<br/>    id           = string<br/>    name         = string<br/>    display_name = string<br/>  }))</pre> | n/a | yes |
| <a name="input_hub_project_id"></a> [hub\_project\_id](#input\_hub\_project\_id) | Project ID for the network hub | `string` | n/a | yes |
| <a name="input_hub_vpc_cidr_block"></a> [hub\_vpc\_cidr\_block](#input\_hub\_vpc\_cidr\_block) | CIDR block for the hub VPC (e.g. "10.0.0.0/16"). Required — set via IPAM or per-environment tfvars. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The GCP organization ID. Accepts either a bare numeric ID (e.g. '123456789012') as returned<br/>by data.google\_organization.org.org\_id, or the 'organizations/<id>' prefixed form.<br/>The module normalizes to the prefixed form internally before passing to VPC-SC. | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Prefix used for project naming | `string` | n/a | yes |
| <a name="input_spoke_project_ids"></a> [spoke\_project\_ids](#input\_spoke\_project\_ids) | Map of spoke project IDs to attach to Shared VPC | `map(string)` | n/a | yes |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | When true (the default), protects hub and DNS VPC resources from accidental deletion via<br/>terraform destroy. Set to false only during a planned teardown.<br/>IMPORTANT: Set to false and apply before attempting to destroy the hub network stack. | `bool` | `true` | no |
| <a name="input_internal_domain"></a> [internal\_domain](#input\_internal\_domain) | Internal domain for private DNS zone (e.g., 'mycompany.com') | `string` | `"internal.local"` | no |
| <a name="input_vpc_sc_access_policy_name"></a> [vpc\_sc\_access\_policy\_name](#input\_vpc\_sc\_access\_policy\_name) | Bare numeric ID of the existing organisation-level Access Context Manager access policy<br/>(e.g. '1234567890'). Required when the hub VPC-SC perimeter is enabled.<br/>Do NOT include the 'accessPolicies/' prefix. | `string` | `null` | no |
| <a name="input_vpc_sc_enable_dry_run"></a> [vpc\_sc\_enable\_dry\_run](#input\_vpc\_sc\_enable\_dry\_run) | When true, the hub VPC-SC perimeter logs violations but does NOT block traffic (dry-run/simulation mode).<br/>When false (the default), the perimeter is ENFORCED.<br/>Only set to true temporarily during the enforcement transition validation window. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns_zone_name"></a> [dns\_zone\_name](#output\_dns\_zone\_name) | Name of the managed private DNS zone |
| <a name="output_hub_dns_domain"></a> [hub\_dns\_domain](#output\_hub\_dns\_domain) | DNS suffix served by the hub DNS project |
| <a name="output_hub_nat_ips"></a> [hub\_nat\_ips](#output\_hub\_nat\_ips) | External NAT IP addresses allocated to the hub Cloud NAT gateway (null if integrated NAT is disabled) |
| <a name="output_hub_subnet_self_links"></a> [hub\_subnet\_self\_links](#output\_hub\_subnet\_self\_links) | Map of private subnet name to self\_link for the hub VPC — useful for Shared VPC service project attachments and peering configuration |
| <a name="output_hub_vpc_name"></a> [hub\_vpc\_name](#output\_hub\_vpc\_name) | Name of the hub VPC |
| <a name="output_hub_vpc_self_link"></a> [hub\_vpc\_self\_link](#output\_hub\_vpc\_self\_link) | Self link of the hub VPC |
<!-- END_TF_DOCS -->
