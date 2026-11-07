# NCC Hub Module

A [Network Connectivity Center](https://cloud.google.com/network-connectivity/docs/network-connectivity-center/concepts/overview)
hub with a preset topology: the opt-in alternative to hub-and-spoke VPC peering.
Composed by `modules/gcp/stages/net-hub` (`ncc.enabled`).

## Features

- **Preset topology**: `policy_mode = PRESET` with `STAR` (default: edge spokes reach the
  center group only, the peering-equivalent isolation) or `MESH` (every spoke reaches every
  other). The topology is immutable; changing it replaces the hub.
- **Service-created groups**: STAR pre-creates `center` and `edge`, MESH `default`. They are
  exposed as `<hub id>/groups/<name>` (`group_ids`) and never managed as resources.
- **PSC propagation**: opt-in `export_psc`.

## Usage

```hcl
module "ncc_hub" {
  source = "../../network/ncc-hub"

  project_id      = "my-hub-project"
  name            = "landing-zone-hub"
  preset_topology = "STAR"
}
```

Attach spokes with [`network/ncc-spoke`](../ncc-spoke/README.md): the hub VPC in
`center_group`, spoke VPCs in `spoke_group`. Migrating existing peerings:
[docs/runbooks/gcp-peering-to-ncc-migration.md](../../../../docs/runbooks/gcp-peering-to-ncc-migration.md).

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

NCC Hub Module - Main Configuration

A Network Connectivity Center hub with a preset connectivity topology, the
opt-in alternative to hub-and-spoke VPC peering. STAR lets every edge spoke
reach the center group but not other edge spokes; MESH lets every spoke reach
every other spoke. The topology is immutable: changing it replaces the hub,
which first requires deleting every spoke attached to it.

The hub's groups are created by the service (STAR: center + edge; MESH:
default). They are referenced by ID (<hub id>/groups/<name>), never managed
here, so this module never fights the service over them.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
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


- resource.google_network_connectivity_hub.this (modules/gcp/network/ncc-hub/main.tf#L22)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Hub name. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project that owns the hub (normally the network hub project). | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | Hub description. | `string` | `"Network Connectivity Center hub managed by Terraform"` | no |
| <a name="input_export_psc"></a> [export\_psc](#input\_export\_psc) | Propagate Private Service Connect endpoint connections across the hub's VPC spokes. | `bool` | `false` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to the hub. | `map(string)` | `{}` | no |
| <a name="input_preset_topology"></a> [preset\_topology](#input\_preset\_topology) | Preset connectivity topology. STAR: edge spokes reach the center group only (hub-and-spoke isolation, the peering-equivalent). MESH: every spoke reaches every other spoke. Immutable: changing it replaces the hub. | `string` | `"STAR"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_center_group"></a> [center\_group](#output\_center\_group) | The group name the hub VPC joins: center for STAR, default for MESH. |
| <a name="output_group_ids"></a> [group\_ids](#output\_group\_ids) | IDs of the service-created groups, keyed by group name (STAR: center, edge; MESH: default). |
| <a name="output_id"></a> [id](#output\_id) | The hub ID (projects/<project>/locations/global/hubs/<name>); pass it to network/ncc-spoke hub\_id. |
| <a name="output_name"></a> [name](#output\_name) | The hub name. |
| <a name="output_preset_topology"></a> [preset\_topology](#output\_preset\_topology) | The hub's preset topology (STAR or MESH). |
| <a name="output_spoke_group"></a> [spoke\_group](#output\_spoke\_group) | The group name a spoke VPC joins: edge for STAR, default for MESH. |
<!-- END_TF_DOCS -->
