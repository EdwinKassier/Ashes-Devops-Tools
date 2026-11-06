/**
 * Copyright 2023 Ashes
 *
 * dns-anchor Module - Outputs
 */

output "network_id" {
  description = "The anchor VPC network ID."
  value       = module.network.network_id
}

output "network_self_link" {
  description = "The anchor VPC network self link (the target for DNS peering zones)."
  value       = module.network.network_self_link
}

output "network_name" {
  description = "The anchor VPC network name."
  value       = module.network.network_name
}

output "subnets" {
  description = "Subnet module outputs by tier (public, private, database), each keyed by zone."
  value       = module.network.subnets
}

output "dns_zones" {
  description = "All DNS zone module outputs, keyed by zone name."
  value       = module.dns_zones
}

output "dns_zone_names" {
  description = "Managed zone name of each DNS zone."
  value       = { for k, v in module.dns_zones : k => v.zone_name }
}

output "dns_names" {
  description = "DNS suffix served by each DNS zone."
  value       = { for k, v in module.dns_zones : k => v.dns_name }
}

output "peering_states" {
  description = "The state of each VPC peering connection."
  value       = { for k, v in module.vpc_peering : k => v.peering_state }
}
