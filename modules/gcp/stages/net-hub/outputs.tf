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

output "interconnect_states" {
  description = "The state of each interconnect attachment."
  value       = { for k, v in module.interconnects : k => v.state }
}

output "interconnect_pairing_keys" {
  description = "Pairing keys for partner interconnects (share with the provider)."
  sensitive   = true
  value       = { for k, v in module.interconnects : k => v.pairing_key }
}
