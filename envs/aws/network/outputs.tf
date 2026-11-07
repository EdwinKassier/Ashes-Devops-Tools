# Network cross-root contract. These keys are consumed by downstream app roots
# via terraform_remote_state. Keep them stable across refactors — renaming a key
# breaks every root that reads it.

locals {
  # The aws-network cross-root contract: ONE non-sensitive object that downstream
  # roots read as .outputs.contract (tfc-admin: tfe_outputs nonsensitive_values
  # .contract). Never put a sensitive value in it: one sensitive attribute moves
  # the whole object into tfe_outputs' sensitive_values. Keys are stable;
  # scripts/check-contracts.sh enforces the read side.
  contract = {
    tgw_id                    = module.aws_network_hub.tgw_id
    ipam_pool_ids             = module.aws_network_hub.ipam_pool_ids
    inspection_vpc_id         = module.aws_network_hub.inspection_vpc_id
    egress_vpc_id             = module.aws_network_hub.egress_vpc_id
    resolver_profile_id       = module.aws_network_hub.resolver_profile_id
    interface_endpoint_phz_id = module.aws_network_hub.interface_endpoint_phz_id
  }
}

output "contract" {
  description = "The aws-network cross-root contract: every key below in one non-sensitive object. Downstream roots read this output only; the individual outputs are deprecated aliases kept until v1.0."
  value       = local.contract
}

output "tgw_id" {
  description = "Deprecated: read contract.tgw_id (removed in v1.0). The ID of the transit gateway (the network cross-root routing contract)."
  value       = local.contract.tgw_id
}

output "ipam_pool_ids" {
  description = "Deprecated: read contract.ipam_pool_ids (removed in v1.0). Map of region to the ID of its regional IPAM pool, consumed by app roots to allocate VPC CIDRs."
  value       = local.contract.ipam_pool_ids
}

output "inspection_vpc_id" {
  description = "Deprecated: read contract.inspection_vpc_id (removed in v1.0). The ID of the inspection VPC that hosts the Network Firewall."
  value       = local.contract.inspection_vpc_id
}

output "egress_vpc_id" {
  description = "Deprecated: read contract.egress_vpc_id (removed in v1.0). The ID of the centralized egress VPC that hosts NAT, interface endpoints, and resolver endpoints."
  value       = local.contract.egress_vpc_id
}

output "resolver_profile_id" {
  description = "Deprecated: read contract.resolver_profile_id (removed in v1.0). The ID of the Route 53 Profile shared org-wide over RAM."
  value       = local.contract.resolver_profile_id
}

output "interface_endpoint_phz_id" {
  description = "Deprecated: read contract.interface_endpoint_phz_id (removed in v1.0). Zone ID of the shared private hosted zone fronting the interface endpoints, or null when no zone was created."
  value       = local.contract.interface_endpoint_phz_id
}
