/**
 * Copyright 2023 Ashes
 *
 * net-spoke Module - Outputs
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

output "additional_firewall_rule_ids" {
  description = "IDs of the additional firewall rules, keyed by rule name."
  value       = { for k, v in module.additional_firewall_rules : k => v.id }
}

output "vpc_peerings" {
  description = "All VPC peering outputs, keyed by peering name."
  value       = module.vpc_peering
}

output "peering_states" {
  description = "The state of each VPC peering connection."
  value       = { for k, v in module.vpc_peering : k => v.peering_state }
}

output "dns_zones" {
  description = "All DNS zone outputs, keyed by zone name."
  value       = module.dns
}

output "dns_name_servers" {
  description = "Name servers for each DNS zone."
  value       = { for k, v in module.dns : k => v.name_servers }
}

output "cloud_armor" {
  description = "The Cloud Armor security policy module outputs, or null when disabled."
  value       = var.edge.cloud_armor.enabled ? module.cloud_armor[0] : null
}

output "security_policy_id" {
  description = "The Cloud Armor security policy ID, or null when disabled."
  value       = var.edge.cloud_armor.enabled ? module.cloud_armor[0].policy_id : null
}

output "security_policy_self_link" {
  description = "The Cloud Armor security policy self link, or null when disabled."
  value       = var.edge.cloud_armor.enabled ? module.cloud_armor[0].policy_self_link : null
}

output "vpc_flow_logs_sink_name" {
  description = "The Cloud Logging sink that exports VPC flow logs, or null when export is disabled."
  value       = var.flow_logs_export.enabled ? module.vpc_flow_logs[0].name : null
}

output "vpc_flow_logs_sink_writer_identity" {
  description = "The sink writer identity to grant on the destination, or null when export is disabled."
  value       = var.flow_logs_export.enabled ? module.vpc_flow_logs[0].writer_identity : null
}

output "vpc_flow_logs_kms_key_name" {
  description = "The CMEK key encrypting exported flow logs, or null when export is disabled."
  value       = var.flow_logs_export.enabled ? module.flow_logs_kms[0].key_names["vpc-flow-logs"] : null
}

output "shared_vpc_service_project_ids" {
  description = "The IDs of the Shared VPC service project attachments, keyed by service project."
  value       = { for k, v in module.shared_vpc_service_projects : k => v.id }
}

output "firewall_policy_name" {
  description = "Name of the tier network firewall policy (pass to network/internal-lb firewall_policy), or null in firewall_mode = legacy."
  value       = module.network.firewall_policy_name
}
