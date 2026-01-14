# =============================================================================
# OUTPUTS
# =============================================================================

output "network_id" {
  description = "The VPC network ID"
  value       = module.host.network_id
}

output "network_self_link" {
  description = "The VPC network self-link"
  value       = module.host.network_self_link
}

output "network_name" {
  description = "The VPC network name"
  value       = module.host.network_name
}

output "subnets" {
  description = "All subnet outputs organized by tier (public, private, database)"
  value       = module.host.subnets
}

output "host_project_id" {
  description = "The host project ID for this environment"
  value       = local.dev_host_project_id
}

output "nat_ip" {
  description = "The NAT gateway IP addresses"
  value       = module.host.nat_ip
}

output "dns_zones" {
  description = "DNS zone outputs"
  value       = module.host.dns_zones
}

output "vpc_peerings" {
  description = "VPC peering connection outputs"
  value       = module.host.vpc_peerings
}
