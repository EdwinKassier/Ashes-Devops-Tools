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

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Cloud VPN Module - Main Configuration

Creates an HA VPN gateway with BGP routing for hybrid connectivity.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	name = 
	network = 
	peer_external_gateway_ip = 
	project_id = 
	region = 
	shared_secret = 
	
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


- resource.google_compute_external_vpn_gateway.peer (modules/network/vpn/main.tf#L26)
- resource.google_compute_ha_vpn_gateway.gateway (modules/network/vpn/main.tf#L14)
- resource.google_compute_router.router (modules/network/vpn/main.tf#L41)
- resource.google_compute_router_interface.interfaces (modules/network/vpn/main.tf#L80)
- resource.google_compute_router_peer.peers (modules/network/vpn/main.tf#L92)
- resource.google_compute_vpn_tunnel.tunnels (modules/network/vpn/main.tf#L62)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Base name for VPN resources | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The self-link of the VPC network | `string` | n/a | yes |
| <a name="input_peer_external_gateway_ip"></a> [peer\_external\_gateway\_ip](#input\_peer\_external\_gateway\_ip) | External IP address of the peer VPN gateway | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The project ID where the VPN will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region for the VPN gateway | `string` | n/a | yes |
| <a name="input_shared_secret"></a> [shared\_secret](#input\_shared\_secret) | Shared secret for IKE authentication | `string` | n/a | yes |
| <a name="input_advertised_ip_ranges"></a> [advertised\_ip\_ranges](#input\_advertised\_ip\_ranges) | Custom IP ranges to advertise via BGP | <pre>list(object({<br/>    range       = string<br/>    description = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to VPN resources | `map(string)` | `{}` | no |
| <a name="input_local_ip_addresses"></a> [local\_ip\_addresses](#input\_local\_ip\_addresses) | List of local BGP IP addresses for each tunnel | `list(string)` | <pre>[<br/>  "169.254.0.1",<br/>  "169.254.1.1"<br/>]</pre> | no |
| <a name="input_peer_asn"></a> [peer\_asn](#input\_peer\_asn) | The ASN of the peer network (for BGP) | `number` | `65001` | no |
| <a name="input_peer_ip_addresses"></a> [peer\_ip\_addresses](#input\_peer\_ip\_addresses) | List of BGP peer IP addresses for each tunnel | `list(string)` | <pre>[<br/>  "169.254.0.2",<br/>  "169.254.1.2"<br/>]</pre> | no |
| <a name="input_router_asn"></a> [router\_asn](#input\_router\_asn) | The ASN for the Cloud Router (BGP) | `number` | `64514` | no |
| <a name="input_router_name"></a> [router\_name](#input\_router\_name) | Name of the Cloud Router (created if not exists) | `string` | `null` | no |
| <a name="input_tunnel_count"></a> [tunnel\_count](#input\_tunnel\_count) | Number of VPN tunnels to create (1 or 2 for HA) | `number` | `2` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bgp_peers"></a> [bgp\_peers](#output\_bgp\_peers) | The BGP peer resources |
| <a name="output_gateway"></a> [gateway](#output\_gateway) | The HA VPN gateway resource |
| <a name="output_gateway_ip_addresses"></a> [gateway\_ip\_addresses](#output\_gateway\_ip\_addresses) | The external IP addresses of the VPN gateway interfaces |
| <a name="output_id"></a> [id](#output\_id) | The ID of the VPN gateway |
| <a name="output_router"></a> [router](#output\_router) | The Cloud Router resource |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The URI of the VPN gateway |
| <a name="output_tunnel_statuses"></a> [tunnel\_statuses](#output\_tunnel\_statuses) | The status of each VPN tunnel |
| <a name="output_tunnels"></a> [tunnels](#output\_tunnels) | The VPN tunnel resources |
<!-- END_TF_DOCS -->