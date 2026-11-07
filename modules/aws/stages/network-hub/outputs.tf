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
  description = "The centralized-inspection routing contract fed to the transit gateway: the segment default routes (0.0.0.0/0) pointed at the inspection attachment so prod and nonprod traffic is forced through the firewall, plus (with spoke_attachments) inspection 0.0.0.0/0 to egress and shared top_cidr to inspection."
  value       = local.tgw_routes
}

output "egress_route_table_ids_by_tier" {
  description = "Map of egress VPC subnet tier to its per-AZ route table IDs (owned by the vpc module)."
  value       = module.egress_vpc.route_table_ids_by_tier
}

output "inspection_route_table_ids_by_tier" {
  description = "Map of inspection VPC subnet tier to its per-AZ route table IDs (owned by the vpc module)."
  value       = module.inspection_vpc.route_table_ids_by_tier
}

output "vpn_connection_id" {
  description = "ID of the Site-to-Site VPN connection, or null when enable_vpn = false."
  value       = try(module.vpn[0].vpn_connection_id, null)
}

output "vpn_tunnel_addresses" {
  description = "AWS-side public IPs of the two VPN tunnels (configure these on the on-premises device), or an empty list when enable_vpn = false."
  value       = var.enable_vpn ? [module.vpn[0].tunnel1_address, module.vpn[0].tunnel2_address] : []
}

output "vpn_preshared_key_arn" {
  description = "ARN of the Secrets Manager secret holding the VPN tunnel pre-shared keys (read it to configure the on-premises device), or null when enable_vpn = false or vpn.preshared_key_storage = Standard."
  value       = try(module.vpn[0].preshared_key_arn, null)
}

output "spoke_attachment_route_tables" {
  description = "Map of spoke_attachments key to the TGW route table its attachment is associated with (prod or nonprod segment); every listed spoke also propagates into the inspection route table."
  value       = { for k, s in var.spoke_attachments : k => module.transit_gateway.route_table_ids[s.segment] }
}
