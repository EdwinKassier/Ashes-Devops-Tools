/**
 * Copyright 2023 Ashes
 *
 * Host Module - Outputs
 */

# =============================================================================
# VPC OUTPUTS
# =============================================================================

output "vpc" {
  description = "The VPC module outputs (if enabled)"
  value       = var.enable_networking ? module.vpc[0] : null
}

output "network_id" {
  description = "The VPC network ID"
  value       = var.enable_networking ? module.vpc[0].id : var.existing_network_id
}

output "network_self_link" {
  description = "The VPC network self link"
  value       = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link
}

output "network_name" {
  description = "The VPC network name"
  value       = var.enable_networking ? module.vpc[0].name : var.existing_network_name
}

output "subnets" {
  description = "All subnet outputs organized by tier"
  value = var.enable_networking ? {
    public   = module.public_subnets
    private  = module.private_subnets
    database = module.database_subnets
  } : null
}

output "network_tags" {
  description = "Network tags for tiered security"
  value       = local.network_tags
}

output "nat_ip" {
  description = "The NAT gateway IP addresses"
  value       = var.enable_networking ? try(module.integrated_nat[0].nat_ips, null) : null
}

