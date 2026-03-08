output "hub_vpc_self_link" {
  description = "Self link of the hub VPC"
  value       = module.hub_network.network_self_link
}

output "hub_vpc_name" {
  description = "Name of the hub VPC"
  value       = module.hub_network.network_name
}

output "dns_zone_name" {
  description = "Name of the managed private DNS zone"
  value       = module.dns_hub_zone.zone_name
}

output "hub_dns_domain" {
  description = "DNS suffix served by the hub DNS project"
  value       = module.dns_hub_zone.dns_name
}
