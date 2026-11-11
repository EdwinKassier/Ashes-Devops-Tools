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
      # Opt-in hub Secure Web Proxy: the PSC service attachment an environment's
      # egress proxy endpoint targets; null while the proxy is off.
      egress_proxy_service_attachment = try(module.network_hub.secure_web_proxy.service_attachment_id, null)
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
      vpc_self_link                   = string
      vpc_name                        = string
      dns_zone_name                   = string
      dns_domain                      = string
      ncc_hub_id                      = string
      ncc_spoke_group                 = string
      egress_proxy_service_attachment = string
    })
  })
  value = local.contract
}

output "hub_network" {
  description = "Deprecated: read contract.hub_network (removed in v1.0). Hub network details for spoke peering and DNS."
  value       = local.contract.hub_network
}

output "spoke_peering_states" {
  description = "State of each hub-side environment peering (hub-to-<env>), keyed by environment key. ACTIVE once gcp-workload-<env> has created the spoke side. An environment missing here has no spoke network yet: queue this workspace again after its first workload apply."
  value       = module.network_hub.spoke_peering_states
}

output "hub_perimeter_projects" {
  description = "Project numbers in the hub VPC-SC perimeter: the hub and DNS projects only. Environment host projects are in their own environment perimeters."
  value       = module.network_hub.hub_perimeter_projects
}

output "secure_web_proxy" {
  description = "The hub Secure Web Proxy (gateway_id, address, ports, service_attachment_id), or null when secure_web_proxy.enabled = false. service_attachment_id is what an environment's egress proxy endpoint targets."
  value       = module.network_hub.secure_web_proxy
}

output "network_alert_policy_ids" {
  description = "Hub data-plane alert policy IDs keyed by alert (vpn_tunnel_down, bgp_session_down, nat_allocation_failed, nat_dropped_packets)."
  value       = module.network_hub.network_alert_policy_ids
}
