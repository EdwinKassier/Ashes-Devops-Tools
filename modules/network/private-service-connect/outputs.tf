/**
 * Copyright 2023 Ashes
 *
 * Private Service Connect Module - Outputs
 */

output "address" {
  description = "The reserved IP address for the PSC endpoint"
  value       = local.is_google_api ? google_compute_global_address.psc_address[0].address : null
}

output "address_id" {
  description = "The ID of the reserved IP address"
  value       = local.is_google_api ? google_compute_global_address.psc_address[0].id : null
}

output "forwarding_rule" {
  description = "The PSC forwarding rule resource"
  value       = local.is_google_api ? google_compute_global_forwarding_rule.psc_forwarding_rule[0] : null
}

output "id" {
  description = "The ID of the PSC forwarding rule"
  value       = local.is_google_api ? google_compute_global_forwarding_rule.psc_forwarding_rule[0].id : null
}

output "self_link" {
  description = "The URI of the PSC forwarding rule"
  value       = local.is_google_api ? google_compute_global_forwarding_rule.psc_forwarding_rule[0].self_link : null
}

output "dns_zone" {
  description = "The private DNS zone for PSC (if created)"
  value       = local.is_google_api && var.create_dns_zone ? google_dns_managed_zone.psc_dns[0] : null
}
