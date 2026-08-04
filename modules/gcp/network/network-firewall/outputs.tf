/**
 * Copyright 2023 Ashes
 *
 * Network Firewall Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the created firewall rule"
  value       = google_compute_firewall.firewall_rule.id
}

output "self_link" {
  description = "The self_link of the created firewall rule"
  value       = google_compute_firewall.firewall_rule.self_link
}

# Legacy outputs (kept for backwards compatibility)
output "firewall_rule_id" {
  description = "The ID of the created firewall rule (deprecated: use 'id' instead)"
  value       = google_compute_firewall.firewall_rule.id
}

output "firewall_rule_self_link" {
  description = "The self_link of the created firewall rule (deprecated: use 'self_link' instead)"
  value       = google_compute_firewall.firewall_rule.self_link
}

output "firewall_rule_creation_timestamp" {
  description = "Creation timestamp of the firewall rule"
  value       = google_compute_firewall.firewall_rule.creation_timestamp
}

output "name" {
  description = "The name of the created firewall rule"
  value       = google_compute_firewall.firewall_rule.name
} 