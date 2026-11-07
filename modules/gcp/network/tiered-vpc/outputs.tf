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

output "additional_region_subnets" {
  description = "Subnet module outputs of the additional regions, keyed by region, each with public, private and database; empty when additional_regions is empty."
  value = {
    for region in keys(var.additional_regions) : region => {
      public   = module.additional_public_subnets[region]
      private  = module.additional_private_subnets[region]
      database = module.additional_database_subnets[region]
    }
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

output "firewall_policy_rules" {
  description = "The tier network firewall policy rules keyed by rule key (priority, direction, action, source/destination ranges, egress target service accounts); empty in firewall_mode = legacy."
  value = {
    for k, r in local.firewall_policy_rules : k => {
      priority                = r.priority
      direction               = r.direction
      action                  = r.action
      src_ip_ranges           = r.src_ip_ranges
      dest_ip_ranges          = r.dest_ip_ranges
      target_service_accounts = r.target_service_accounts
    }
  }
}
