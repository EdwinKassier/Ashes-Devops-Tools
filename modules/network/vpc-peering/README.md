# VPC Peering Module

This module manages VPC Network Peering connections, including bi-directional setup and route exchange configuration.

## Features

- **Bi-directional Peering**: Automatically creates the peering on both the local and peer networks (optional).
- **Route Exchange**: Configurable import/export of custom routes.
- **Public IP Routes**: Configurable import/export of subnet routes with public IPs.
- **Stack Type**: Supports IPv4 only or IPv4/IPv6 stacks.

## Usage

```hcl
module "peering_hub_spoke" {
  source = "./modules/network/vpc-peering"

  project_id   = "hub-project"
  peering_name = "hub-to-spoke"
  network      = "projects/hub-project/global/networks/hub-vpc"
  peer_network = "projects/spoke-project/global/networks/spoke-vpc"

  # Create the reverse connection automatically
  create_reverse_peering = true
  peer_project_id        = "spoke-project"
  
  export_custom_routes = true
  import_custom_routes = true
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID of the local network | `string` | n/a | yes |
| `peering_name` | Name of the peering connection | `string` | n/a | yes |
| `network` | Local network self-link | `string` | n/a | yes |
| `peer_network` | Peer network self-link | `string` | n/a | yes |
| `create_reverse_peering` | specific create the reverse connection | `bool` | `true` | no |
| `peer_project_id` | Project ID of the peer network | `string` | `null` | no |
| `export_custom_routes` | Export local custom routes | `bool` | `false` | no |
| `import_custom_routes` | Import peer custom routes | `bool` | `false` | no |
| `stack_type` | IP stack type (`IPV4_ONLY`) | `string` | `"IPV4_ONLY"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `peering` | The primary peering connection resource |
| `reverse_peering` | The reverse peering connection resource (if created) |
| `peering_state` | State of the peering (ACTIVE/INACTIVE) |
