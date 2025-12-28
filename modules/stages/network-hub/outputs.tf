output "hub_vpc_self_link" {
  value = module.hub_network.network_self_link
}

output "hub_vpc_name" {
  value = module.hub_network.network_name
}

output "dns_zone_name" {
  value = module.dns_hub_zone.name
}
