/**
 * Copyright 2023 Ashes
 *
 * net-hub Module - Outputs
 */

output "vpc" {
  description = "The composed VPC module outputs."
  value       = module.network.vpc
}

output "network_id" {
  description = "The VPC network ID."
  value       = module.network.network_id
}

output "network_self_link" {
  description = "The VPC network self link."
  value       = module.network.network_self_link
}

output "network_name" {
  description = "The VPC network name."
  value       = module.network.network_name
}

output "subnets" {
  description = "Subnet module outputs by tier (public, private, database), each keyed by zone."
  value       = module.network.subnets
}

output "additional_region_subnets" {
  description = "Subnet module outputs of the additional regions, keyed by region, each with public, private and database; empty when additional_regions is empty."
  value       = module.network.additional_region_subnets
}

output "additional_region_routers" {
  description = "Cloud Router name per additional region that has Cloud NAT, keyed by region; empty when there is none."
  value       = { for region, n in module.additional_region_nat : region => n.router_name }
}

output "network_tags" {
  description = "Network tags that select the security tiers in the baseline firewall rules."
  value       = module.network.network_tags
}

output "nat_ip" {
  description = "The Cloud NAT IP addresses, or null when NAT is disabled."
  value       = try(module.integrated_nat[0].nat_ips, null)
}

output "private_service_access_range_name" {
  description = "Name of the Private Service Access range reserved on this VPC, or null when PSA is disabled."
  value       = var.private_service_access.enabled ? module.private_service_access[0].address_resource.name : null
}

output "vpc_service_controls" {
  description = "All VPC Service Controls perimeter outputs, keyed by perimeter name."
  value       = module.vpc_service_controls
}

output "vpc_service_control_perimeter_names" {
  description = "The names of all VPC Service Controls perimeters."
  value       = { for k, v in module.vpc_service_controls : k => v.name }
}

output "hierarchical_firewall_policy_ids" {
  description = "The IDs of the hierarchical firewall policies, keyed by policy name."
  value       = { for k, v in module.hierarchical_firewall_policies : k => v.id }
}

output "vpn_gateway_ips" {
  description = "The HA VPN gateway external IP addresses, or null when VPN is disabled."
  value       = var.vpn.enabled ? module.vpn[0].gateway_ip_addresses : null
}

output "vpn_tunnel_statuses" {
  description = "The status of each VPN tunnel, or null when VPN is disabled."
  value       = var.vpn.enabled ? module.vpn[0].tunnel_statuses : null
}

output "ncc_vpn_spoke_id" {
  description = "ID of the NCC hybrid spoke for the HA VPN tunnels, or null unless both ncc.enabled and vpn.enabled."
  value       = try(module.ncc_vpn_spoke[0].id, null)
}

output "hybrid_connectivity" {
  description = "Which hybrid connectivity is planned: vpn (HA VPN on), ncc_vpn_spoke (tunnels linked to the NCC hub), ncc_vpn_spoke_group and the interconnect attachment names."
  value = {
    vpn           = length(module.vpn) > 0
    ncc_vpn_spoke = length(module.ncc_vpn_spoke) > 0
    # The NCC group the hybrid spoke joins: center (STAR) or default (MESH).
    ncc_vpn_spoke_group = length(module.ncc_vpn_spoke) > 0 ? local.ncc_vpn_spoke_group : null
    interconnects       = sort(keys(module.interconnects))
  }
}

output "interconnect_states" {
  description = "The state of each interconnect attachment."
  value       = { for k, v in module.interconnects : k => v.state }
}

output "interconnect_pairing_keys" {
  description = "Pairing keys for partner interconnects (share with the provider)."
  sensitive   = true
  value       = { for k, v in module.interconnects : k => v.pairing_key }
}

output "firewall_policy_name" {
  description = "Name of the tier network firewall policy (pass to network/internal-lb firewall_policy), or null in firewall_mode = legacy."
  value       = module.network.firewall_policy_name
}

output "ncc_hub_id" {
  description = "The NCC hub ID that environment spokes attach to (stages/net-spoke ncc.hub_id), or null when ncc.enabled = false."
  value       = try(module.ncc_hub[0].id, null)
}

output "ncc_spoke_group" {
  description = "The NCC group environment spokes join (edge for STAR, default for MESH), or null when ncc.enabled = false."
  value       = try(module.ncc_hub[0].spoke_group, null)
}

output "nat_subnet_tiers" {
  description = "Subnet tiers the primary Cloud NAT translates (private, plus database only with nat.include_database_subnets); empty when NAT is disabled."
  value       = var.nat.enabled ? concat(["private"], var.nat.include_database_subnets ? ["database"] : []) : []
}

output "secure_web_proxy" {
  description = "The hub Secure Web Proxy: gateway_id, address (known after apply unless set), ports and service_attachment_id (target for spoke PSC endpoints, null when not published). Null when secure_web_proxy.enabled = false."
  value = var.secure_web_proxy.enabled ? {
    gateway_id            = module.secure_web_proxy[0].gateway_id
    address               = module.secure_web_proxy[0].gateway_address
    ports                 = module.secure_web_proxy[0].gateway_ports
    service_attachment_id = module.secure_web_proxy[0].service_attachment_id
  } : null
}

output "network_alert_policy_ids" {
  description = "Data-plane alert policy IDs keyed by alert (vpn_tunnel_down, bgp_session_down, nat_allocation_failed, nat_dropped_packets); empty when alerting is off or no watched feature exists."
  value       = try(module.network_alerts[0].all_alert_policy_ids, {})
}
