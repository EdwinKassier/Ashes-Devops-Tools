# Cloud VPN Module

This module provisions a High Availability (HA) Cloud VPN Gateway with BGP routing via Cloud Router.

## Features

- **HA VPN**: Deploys an HA VPN Gateway with 99.99% SLA.
- **BGP Routing**: Automatically configures Cloud Router and BGP sessions.
- **Redundancy**: Supports dual-tunnel configuration for failover.
- **Custom Advertisement**: Configure custom IP ranges to advertise over BGP.

## Usage

```hcl
module "vpn_ha" {
  source = "./modules/network/vpn"

  project_id = "my-project-id"
  name       = "on-prem-vpn"
  network    = "projects/my-project/global/networks/my-vpc"
  region     = "us-central1"

  # Peer Details
  peer_external_gateway_ip = "203.0.113.1"
  peer_asn                 = 65001
  shared_secret            = "super-secret-key"

  # BGP Configuration
  peer_ip_addresses  = ["169.254.0.2", "169.254.1.2"]
  local_ip_addresses = ["169.254.0.1", "169.254.1.1"]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID where the VPN will be created | `string` | n/a | yes |
| `name` | Base name for VPN resources | `string` | n/a | yes |
| `network` | VPC network self-link | `string` | n/a | yes |
| `region` | GCP Region | `string` | n/a | yes |
| `peer_external_gateway_ip` | Public IP of the peer gateway | `string` | n/a | yes |
| `shared_secret` | IKE Shared Secret | `string` | n/a | yes |
| `router_asn` | Local BGP ASN | `number` | `64514` | no |
| `peer_asn` | Remote BGP ASN | `number` | `65001` | no |
| `tunnel_count` | Number of tunnels (1 or 2) | `number` | `2` | no |
| `peer_ip_addresses` | List of BGP peer IPs | `list(string)` | `[...]` | no |
| `local_ip_addresses` | List of BGP local IPs | `list(string)` | `[...]` | no |
| `advertised_ip_ranges` | Custom BGP advertisements | `list(object)` | `[]` | no |
| `labels` | Labels to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `gateway` | The HA VPN Gateway resource |
| `gateway_ip_addresses` | Public IPs of the VPN interfaces |
| `tunnels` | List of created VPN tunnels |
| `router` | The Cloud Router resource |
