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
