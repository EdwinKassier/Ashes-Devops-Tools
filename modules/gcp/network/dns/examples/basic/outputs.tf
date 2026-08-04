output "zone_name_servers" {
  description = "Name servers assigned to the zone (empty for private zones)"
  value       = module.internal_dns.name_servers
}
