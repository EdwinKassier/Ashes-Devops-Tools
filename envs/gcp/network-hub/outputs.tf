# Cross-root contract (Convention 4). Consumed by gcp-workload for hub peering
# (or the NCC hub) and internal DNS resolution. Keep these keys stable.

locals {
  # The gcp-network-hub cross-root contract: ONE non-sensitive object that downstream
  # roots read as .outputs.contract (tfc-admin: tfe_outputs nonsensitive_values
  # .contract). Never put a sensitive value in it: one sensitive attribute moves
  # the whole object into tfe_outputs' sensitive_values. Keys are stable;
  # scripts/check-contracts.sh enforces the read side.
  contract = {
    hub_network = {
      vpc_self_link = module.network_hub.hub_vpc_self_link
      vpc_name      = module.network_hub.hub_vpc_name
      dns_zone_name = module.network_hub.dns_zone_name
      dns_domain    = module.network_hub.hub_dns_domain
      # Opt-in NCC hub that environment VPCs join with network_connectivity =
      # ncc (and the group they join); null while the hub is off.
      ncc_hub_id      = module.network_hub.ncc_hub_id
      ncc_spoke_group = module.network_hub.ncc_spoke_group
    }
  }
}

output "contract" {
  description = "The gcp-network-hub cross-root contract: every key below in one non-sensitive object. Downstream roots read this output only; the individual outputs are deprecated aliases kept until v1.0."
  # Exact shape: a key added to local.contract must be added here too, or the
  # conversion drops it silently. scripts/check-contracts.sh compares the
  # top-level keys only: add a NESTED attribute to the type by hand as well.
  type = object({
    hub_network = object({
      vpc_self_link   = string
      vpc_name        = string
      dns_zone_name   = string
      dns_domain      = string
      ncc_hub_id      = string
      ncc_spoke_group = string
    })
  })
  value = local.contract
}

output "hub_network" {
  description = "Deprecated: read contract.hub_network (removed in v1.0). Hub network details for spoke peering and DNS."
  value       = local.contract.hub_network
}
