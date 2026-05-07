output "hub_vpc_self_link" {
  description = "Self link of the hub VPC"
  value       = module.hub_network.network_self_link
}

output "hub_vpc_name" {
  description = "Name of the hub VPC"
  value       = module.hub_network.network_name
}

output "hub_subnet_self_links" {
  description = "Map of private subnet name to self_link for the hub VPC — useful for Shared VPC service project attachments and peering configuration"
  value = module.hub_network.subnets != null ? {
    for k, v in module.hub_network.subnets.private : k => v.self_link
  } : {}
}

output "hub_nat_ips" {
  description = "External NAT IP addresses allocated to the hub Cloud NAT gateway (null if integrated NAT is disabled)"
  value       = module.hub_network.nat_ip
}

output "dns_zone_name" {
  description = "Name of the managed private DNS zone"
  value       = module.dns_hub_zone.zone_name
}

output "hub_dns_domain" {
  description = "DNS suffix served by the hub DNS project"
  value       = module.dns_hub_zone.dns_name
}
