output "tgw_id" {
  description = "The ID of the transit gateway (the network cross-root routing contract)."
  value       = module.transit_gateway.tgw_id
}

output "ipam_pool_ids" {
  description = "Map of region to the ID of its regional IPAM pool, consumed by app roots to allocate VPC CIDRs."
  value       = module.ipam.regional_pool_ids
}

output "inspection_vpc_id" {
  description = "The ID of the inspection VPC that hosts the Network Firewall."
  value       = module.inspection_vpc.vpc_id
}

output "egress_vpc_id" {
  description = "The ID of the centralized egress VPC that hosts NAT, interface endpoints, and resolver endpoints."
  value       = module.egress_vpc.vpc_id
}

output "resolver_profile_id" {
  description = "The ID of the Route 53 Profile shared org-wide over RAM."
  value       = module.route53_resolver.resolver_profile_id
}

output "interface_endpoint_phz_id" {
  description = "Zone ID of the shared private hosted zone fronting the interface endpoints, or null when no zone was created."
  value       = module.vpc_endpoints.phz_id
}

output "tgw_inspection_routes" {
  description = "The centralized-inspection routing contract fed to the transit gateway: the segment default routes (0.0.0.0/0) pointed at the inspection attachment so prod and nonprod traffic is forced through the firewall."
  value       = local.tgw_routes
}
