/**
 * Copyright 2023 Ashes
 *
 * Cloud DNS Module - Outputs
 */

output "zone" {
  description = "The created DNS managed zone resource"
  value       = google_dns_managed_zone.zone
}

output "id" {
  description = "The ID of the DNS managed zone"
  value       = google_dns_managed_zone.zone.id
}

output "self_link" {
  description = "The ID of the DNS managed zone (DNS zones use id rather than self_link)"
  value       = google_dns_managed_zone.zone.id
}

output "zone_name" {
  description = "The name of the DNS zone"
  value       = google_dns_managed_zone.zone.name
}

output "dns_name" {
  description = "The DNS name of the zone"
  value       = google_dns_managed_zone.zone.dns_name
}

output "name_servers" {
  description = "The name servers for this zone (for public zones)"
  value       = google_dns_managed_zone.zone.name_servers
}

output "records" {
  description = "The created DNS record sets"
  value       = google_dns_record_set.records
}
