# Cloud DNS Module

This module manages Google Cloud DNS Managed Zones and Record Sets.

## Features

- **Public and Private Zones**: Create internet-facing or internal-only DNS zones.
- **DNSSEC**: Easy toggle for automatic DNSSEC configuration.
- **Logging**: Configurable query logging.
- **Forwarding**: Support for forwarding zones to other name servers.
- **Record Management**: Dynamic creation of DNS records within the zone.

## Usage

```hcl
module "dns_private_zone" {
  source = "./modules/network/dns"

  project_id = "my-project-id"
  zone_name  = "private-example-com"
  dns_name   = "internal.example.com."
  visibility = "private"

  private_visibility_networks = [
    "projects/my-project/global/networks/my-vpc"
  ]

  records = [
    {
      name    = "app.internal.example.com."
      type    = "A"
      ttl     = 300
      rrdatas = ["10.0.1.5"]
    }
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID where the zone will be created | `string` | n/a | yes |
| `zone_name` | Name of the DNS zone resource | `string` | n/a | yes |
| `dns_name` | DNS suffix (must end with dot) | `string` | n/a | yes |
| `visibility` | Zone visibility (`public` or `private`) | `string` | `"private"` | no |
| `private_visibility_networks` | List of VPC self-links for private visibility | `list(string)` | `[]` | no |
| `description` | Description of the zone | `string` | `"Private DNS zone..."` | no |
| `dnssec_enabled` | Enable DNSSEC (public zones only) | `bool` | `false` | no |
| `enable_logging` | Enable query logging | `bool` | `false` | no |
| `records` | List of DNS records to create | `list(object)` | `[]` | no |
| `forwarding_targets` | List of IPs for forwarding zones | `list(string)` | `[]` | no |
| `labels` | Labels to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `managed_zone` | The full managed zone resource |
| `name_servers` | The list of name servers delegated to the zone |
| `name` | The zone name |
| `domain` | The DNS name |

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Cloud DNS Module - Main Configuration

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	dns_name = 
	project_id = 
	zone_name = 
	
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


- resource.google_dns_managed_zone.private_zone (modules/network/dns/main.tf#L12)
- resource.google_dns_managed_zone.public_zone (modules/network/dns/main.tf#L67)
- resource.google_dns_record_set.records (modules/network/dns/main.tf#L94)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_dns_name"></a> [dns\_name](#input\_dns\_name) | The DNS name of this managed zone (e.g., 'internal.company.com.') | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The project ID where the DNS zone will be created | `string` | n/a | yes |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Name of the DNS zone (used as resource identifier) | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | Description of the DNS zone | `string` | `"Private DNS zone managed by Terraform"` | no |
| <a name="input_dnssec_enabled"></a> [dnssec\_enabled](#input\_dnssec\_enabled) | Enable DNSSEC for public zones. Private zones ignore this setting. | `bool` | `true` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Enable query logging for the zone | `bool` | `false` | no |
| <a name="input_forwarding_targets"></a> [forwarding\_targets](#input\_forwarding\_targets) | List of forwarding target IP addresses (for forwarding zones) | `list(string)` | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the DNS zone | `map(string)` | `{}` | no |
| <a name="input_peering_network"></a> [peering\_network](#input\_peering\_network) | The target VPC network for a peering zone (required when type is 'peering') | `string` | `""` | no |
| <a name="input_private_visibility_networks"></a> [private\_visibility\_networks](#input\_private\_visibility\_networks) | List of VPC network self-links that can see this private zone | `list(string)` | `[]` | no |
| <a name="input_records"></a> [records](#input\_records) | DNS records to create in the zone | <pre>list(object({<br/>    name    = string<br/>    type    = string<br/>    ttl     = optional(number, 300)<br/>    rrdatas = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_visibility"></a> [visibility](#input\_visibility) | Zone visibility: 'public' or 'private' | `string` | `"private"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns_name"></a> [dns\_name](#output\_dns\_name) | The DNS name of the zone |
| <a name="output_id"></a> [id](#output\_id) | The ID of the DNS managed zone |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | The name servers for this zone (for public zones) |
| <a name="output_records"></a> [records](#output\_records) | The created DNS record sets |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The ID of the DNS managed zone (DNS zones use id rather than self\_link) |
| <a name="output_zone"></a> [zone](#output\_zone) | The created DNS managed zone resource |
| <a name="output_zone_name"></a> [zone\_name](#output\_zone\_name) | The name of the DNS zone |
<!-- END_TF_DOCS -->