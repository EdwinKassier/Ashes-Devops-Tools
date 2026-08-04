# Network cross-root contract. These keys are consumed by downstream app roots
# via terraform_remote_state. Keep them stable across refactors — renaming a key
# breaks every root that reads it.

output "tgw_id" {
  description = "The ID of the transit gateway (the network cross-root routing contract)."
  value       = module.aws_network_hub.tgw_id
}

output "ipam_pool_ids" {
  description = "Map of region to the ID of its regional IPAM pool, consumed by app roots to allocate VPC CIDRs."
  value       = module.aws_network_hub.ipam_pool_ids
}

output "inspection_vpc_id" {
  description = "The ID of the inspection VPC that hosts the Network Firewall."
  value       = module.aws_network_hub.inspection_vpc_id
}

output "egress_vpc_id" {
  description = "The ID of the centralized egress VPC that hosts NAT, interface endpoints, and resolver endpoints."
  value       = module.aws_network_hub.egress_vpc_id
}

output "resolver_profile_id" {
  description = "The ID of the Route 53 Profile shared org-wide over RAM."
  value       = module.aws_network_hub.resolver_profile_id
}

output "interface_endpoint_phz_id" {
  description = "Zone ID of the shared private hosted zone fronting the interface endpoints, or null when no zone was created."
  value       = module.aws_network_hub.interface_endpoint_phz_id
}
