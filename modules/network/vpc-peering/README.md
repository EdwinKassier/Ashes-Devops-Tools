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

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

VPC Peering Module - Main Configuration

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	network = 
	peer_network = 
	peering_name = 
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


- resource.google_compute_network_peering.peering (modules/network/vpc-peering/main.tf#L12)
- resource.google_compute_network_peering.reverse_peering (modules/network/vpc-peering/main.tf#L25)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_network"></a> [network](#input\_network) | The self-link of the local VPC network | `string` | n/a | yes |
| <a name="input_peer_network"></a> [peer\_network](#input\_peer\_network) | The self-link of the peer VPC network | `string` | n/a | yes |
| <a name="input_peering_name"></a> [peering\_name](#input\_peering\_name) | Name of the VPC peering connection | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The project ID where the peering will be created | `string` | n/a | yes |
| <a name="input_create_reverse_peering"></a> [create\_reverse\_peering](#input\_create\_reverse\_peering) | Create the reverse peering connection (for bi-directional peering) | `bool` | `true` | no |
| <a name="input_export_custom_routes"></a> [export\_custom\_routes](#input\_export\_custom\_routes) | Export custom routes to the peer network | `bool` | `false` | no |
| <a name="input_export_subnet_routes_with_public_ip"></a> [export\_subnet\_routes\_with\_public\_ip](#input\_export\_subnet\_routes\_with\_public\_ip) | Export subnet routes with public IP range to the peer network | `bool` | `true` | no |
| <a name="input_import_custom_routes"></a> [import\_custom\_routes](#input\_import\_custom\_routes) | Import custom routes from the peer network | `bool` | `false` | no |
| <a name="input_import_subnet_routes_with_public_ip"></a> [import\_subnet\_routes\_with\_public\_ip](#input\_import\_subnet\_routes\_with\_public\_ip) | Import subnet routes with public IP range from the peer network | `bool` | `false` | no |
| <a name="input_peer_project_id"></a> [peer\_project\_id](#input\_peer\_project\_id) | The project ID of the peer network (if different from project\_id) | `string` | `null` | no |
| <a name="input_stack_type"></a> [stack\_type](#input\_stack\_type) | The stack type for the peering (IPV4\_ONLY or IPV4\_IPV6) | `string` | `"IPV4_ONLY"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | The ID of the peering connection |
| <a name="output_peering"></a> [peering](#output\_peering) | The primary peering connection resource |
| <a name="output_peering_name"></a> [peering\_name](#output\_peering\_name) | The name of the primary peering connection |
| <a name="output_peering_state"></a> [peering\_state](#output\_peering\_state) | State of the primary peering (ACTIVE, INACTIVE) |
| <a name="output_peering_state_details"></a> [peering\_state\_details](#output\_peering\_state\_details) | Details about the peering state |
| <a name="output_reverse_peering"></a> [reverse\_peering](#output\_reverse\_peering) | The reverse peering connection resource (if created) |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The network self\_link associated with the peering |
<!-- END_TF_DOCS -->