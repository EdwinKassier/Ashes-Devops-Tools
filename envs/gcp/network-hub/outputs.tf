# Cross-root contract (Convention 4). Consumed by gcp-workload for hub peering
# and internal DNS resolution. Keep these keys stable.

output "hub_network" {
  description = "Hub network details for spoke peering and DNS."
  value = {
    vpc_self_link = module.network_hub.hub_vpc_self_link
    vpc_name      = module.network_hub.hub_vpc_name
    dns_zone_name = module.network_hub.dns_zone_name
    dns_domain    = module.network_hub.hub_dns_domain
  }
}
