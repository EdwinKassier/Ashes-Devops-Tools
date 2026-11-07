# Example: a STAR hub in the network hub project. Spokes attach with
# network/ncc-spoke (hub VPC in the center group, spoke VPCs in edge).

module "ncc_hub" {
  source = "../../"

  project_id      = "my-hub-project"
  name            = "landing-zone-hub"
  preset_topology = "STAR"
}
