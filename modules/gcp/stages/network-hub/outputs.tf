output "hub_vpc_self_link" {
  description = "Self link of the hub VPC"
  value       = module.hub.network_self_link
}

output "hub_vpc_name" {
  description = "Name of the hub VPC"
  value       = module.hub.network_name
}

output "hub_subnet_self_links" {
  description = "Map of private subnet name to self_link for the hub VPC — useful for Shared VPC service project attachments and peering configuration"
  value       = { for k, v in module.hub.subnets.private : k => v.self_link }
}

output "hub_nat_ips" {
  description = "External NAT IP addresses allocated to the hub Cloud NAT gateway (null if integrated NAT is disabled)"
  value       = module.hub.nat_ip
}

output "dns_zone_name" {
  description = "Name of the managed private DNS zone"
  value       = module.dns_anchor.dns_zone_names["internal-root"]
}

output "hub_dns_domain" {
  description = "DNS suffix served by the hub DNS project"
  value       = module.dns_anchor.dns_names["internal-root"]
}

output "hierarchical_firewall_association_targets" {
  description = "Folders the hub SSH/RDP-from-internet deny policy is associated with (shared + every environment folder)."
  value       = local.firewall_association_targets
}

output "ncc_hub_id" {
  description = "ID of the Network Connectivity Center hub environment spokes attach to, or null when enable_ncc_hub = false."
  value       = module.hub.ncc_hub_id
}

output "ncc_spoke_group" {
  description = "NCC group environment spokes join (edge for STAR, default for MESH), or null when enable_ncc_hub = false."
  value       = module.hub.ncc_spoke_group
}
