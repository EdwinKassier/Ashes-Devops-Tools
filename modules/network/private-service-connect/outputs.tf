/**
 * Copyright 2023 Ashes
 *
 * Private Service Connect Module - Outputs
 */

output "address" {
  description = "The reserved IP address for the PSC endpoint"
  value       = google_compute_global_address.psc_address.address
}

output "address_id" {
  description = "The ID of the reserved IP address"
  value       = google_compute_global_address.psc_address.id
}

output "forwarding_rule" {
  description = "The PSC forwarding rule resource"
  value       = google_compute_global_forwarding_rule.psc_forwarding_rule
}

output "id" {
  description = "The ID of the PSC forwarding rule"
  value       = google_compute_global_forwarding_rule.psc_forwarding_rule.id
}

output "self_link" {
  description = "The URI of the PSC forwarding rule"
  value       = google_compute_global_forwarding_rule.psc_forwarding_rule.self_link
}

output "dns_zone" {
  description = "The private DNS zone for PSC (if created)"
  value       = var.create_dns_zone ? google_dns_managed_zone.psc_dns[0] : null
}
