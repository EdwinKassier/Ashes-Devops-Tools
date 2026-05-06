# Example: create a bidirectional VPC peering between two networks.
# Pass create_reverse_peering = true to manage both sides of the peering
# in a single module call (only valid when both networks are in the same project).

locals {
  project_id   = "my-project"
  network_a    = "projects/my-project/global/networks/vpc-a"
  network_b    = "projects/my-project/global/networks/vpc-b"
}

module "vpc_peering" {
  source = "../../"

  project_id   = local.project_id
  peering_name = "vpc-a-to-vpc-b"
  network      = local.network_a
  peer_network = local.network_b

  # Manage the reverse peering (vpc-b → vpc-a) in the same module call.
  # Set to false if the peer network is in a different project and manage
  # the reverse side with a separate module call from that project.
  create_reverse_peering = true
}

output "peering_state" {
  description = "Peering state (ACTIVE once both sides are configured)"
  value       = module.vpc_peering.peering_state
}
