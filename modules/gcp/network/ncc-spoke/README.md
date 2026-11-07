# NCC Spoke Module

One [Network Connectivity Center](https://cloud.google.com/network-connectivity/docs/network-connectivity-center/concepts/overview)
spoke on a hub group, plus optional producer VPC spokes for Private Service Access.
Composed by `modules/gcp/stages/net-hub` (the hub VPC, `center` group) and
`modules/gcp/stages/net-spoke` (`connectivity = "ncc"`, `edge` group).

## Features

- **VPC spoke** (`linked_vpc_network`, location `global`) with include/exclude export ranges.
- **VPN spoke** (`linked_vpn_tunnels`, location = the tunnels' region).
- **Producer VPC spokes** (`producer_vpc_networks`): one per PSA peering
  (`google_service_networking_connection.<x>.peering`). Each reads its hub and group from the
  VPC spoke, so it joins the same group and is created after it, as NCC requires.
- The group is passed by name (`center`, `edge` or `default`) and resolved to
  `<hub id>/groups/<name>`.

NCC rejects a VPC spoke whose VPC is still peered with another VPC spoke of the hub; see
[docs/runbooks/gcp-peering-to-ncc-migration.md](../../../../docs/runbooks/gcp-peering-to-ncc-migration.md).

## Usage

```hcl
module "ncc_spoke" {
  source = "../../network/ncc-spoke"

  project_id = "my-spoke-project"
  name       = "dev-vpc"
  hub_id     = module.ncc_hub.id
  group      = "edge"

  linked_vpc_network = {
    uri = module.network.network_self_link
  }

  producer_vpc_networks = {
    psa = {
      network = module.network.network_name
      peering = module.private_service_access.peering.peering
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

NCC Spoke Module - Main Configuration

One Network Connectivity Center spoke attached to a hub group, linking
either a VPC network (global) or a set of HA VPN tunnels (regional), plus
optional producer VPC spokes for the VPC's Private Service Access peerings.

Producer spokes read hub and group from the consumer VPC spoke, so they
always join the same group and are created only after it: NCC rejects a
producer VPC spoke whose consumer VPC is not already a spoke.

NCC also rejects a VPC spoke whose VPC is still peered with another VPC
spoke; see docs/runbooks/gcp-peering-to-ncc-migration.md.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	hub_id =
	name =
	project_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |



## Resources

The following resources are created:


- resource.google_network_connectivity_spoke.producer (modules/gcp/network/ncc-spoke/main.tf#L63)
- resource.google_network_connectivity_spoke.this (modules/gcp/network/ncc-spoke/main.tf#L32)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_hub_id"></a> [hub\_id](#input\_hub\_id) | ID of the hub to attach to (network/ncc-hub id: projects/<project>/locations/global/hubs/<name>). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Spoke name. Producer spokes are named <name>-<producer\_vpc\_networks key>. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project that owns the spoke (the project of the linked VPC or VPN tunnels). | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | Spoke description. | `string` | `"Network Connectivity Center spoke managed by Terraform"` | no |
| <a name="input_group"></a> [group](#input\_group) | Hub group the spoke joins. STAR hubs: center (the hub VPC) or edge (spoke VPCs). MESH hubs: default. | `string` | `"edge"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to the spoke and its producer spokes. | `map(string)` | `{}` | no |
| <a name="input_linked_vpc_network"></a> [linked\_vpc\_network](#input\_linked\_vpc\_network) | VPC network to link (uri = the network self link). Set exactly one of linked\_vpc\_network or linked\_vpn\_tunnels. Export ranges filter which subnet ranges the hub learns. | <pre>object({<br/>    uri                   = string<br/>    include_export_ranges = optional(list(string), [])<br/>    exclude_export_ranges = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_linked_vpn_tunnels"></a> [linked\_vpn\_tunnels](#input\_linked\_vpn\_tunnels) | HA VPN tunnels to link (self links, all in var.location). site\_to\_site\_data\_transfer must stay false unless the region supports it and data transfer between sites is intended. | <pre>object({<br/>    uris                       = list(string)<br/>    site_to_site_data_transfer = optional(bool, false)<br/>    include_import_ranges      = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | Spoke location: global for a VPC spoke, the tunnels' region for a VPN spoke. | `string` | `"global"` | no |
| <a name="input_producer_vpc_networks"></a> [producer\_vpc\_networks](#input\_producer\_vpc\_networks) | Producer VPC spokes for the linked VPC's Private Service Access peerings, keyed by a short name (for example psa). network = the consumer VPC name; peering = the service networking peering name (google\_service\_networking\_connection.<x>.peering). Requires linked\_vpc\_network; each joins the same group as the VPC spoke. | <pre>map(object({<br/>    network               = string<br/>    peering               = string<br/>    include_export_ranges = optional(list(string), [])<br/>    exclude_export_ranges = optional(list(string), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_group"></a> [group](#output\_group) | The hub group ID the spoke (and its producer spokes) joined. |
| <a name="output_id"></a> [id](#output\_id) | The spoke ID. |
| <a name="output_name"></a> [name](#output\_name) | The spoke name. |
| <a name="output_producer_spoke_ids"></a> [producer\_spoke\_ids](#output\_producer\_spoke\_ids) | Producer VPC spoke IDs, keyed by producer\_vpc\_networks key. |
| <a name="output_state"></a> [state](#output\_state) | The spoke state (ACTIVE once accepted; a spoke in another project than the hub stays PENDING until the hub admin accepts it). |
<!-- END_TF_DOCS -->
