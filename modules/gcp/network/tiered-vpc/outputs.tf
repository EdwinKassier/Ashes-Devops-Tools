/**
 * Copyright 2023 Ashes
 *
 * Tiered VPC Module - Outputs
 */

output "vpc" {
  description = "The composed VPC module outputs."
  value       = module.vpc
}

output "network_id" {
  description = "The VPC network ID."
  value       = module.vpc.id
}

output "network_self_link" {
  description = "The VPC network self link."
  value       = module.vpc.self_link
}

output "network_name" {
  description = "The VPC network name."
  value       = module.vpc.name
}

output "subnets" {
  description = "Subnet module outputs by tier (public, private, database), each keyed by zone."
  value = {
    public   = module.public_subnets
    private  = module.private_subnets
    database = module.database_subnets
  }
}

output "network_tags" {
  description = "Network tags that select the security tiers in the baseline firewall rules."
  value       = local.network_tags
}

output "firewall_policy_id" {
  description = "ID of the tier network firewall policy, or null in firewall_mode = legacy."
  value       = local.create_firewall_policy ? google_compute_network_firewall_policy.tier[0].id : null
}

output "firewall_policy_name" {
  description = "Name of the tier network firewall policy (pass to network/internal-lb firewall_policy), or null in firewall_mode = legacy."
  value       = local.create_firewall_policy ? google_compute_network_firewall_policy.tier[0].name : null
}
