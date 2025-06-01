output "firewall_rule_id" {
  description = "The ID of the created firewall rule"
  value       = google_compute_firewall.firewall_rule.id
}

output "firewall_rule_self_link" {
  description = "The self_link of the created firewall rule"
  value       = google_compute_firewall.firewall_rule.self_link
}

output "firewall_rule_creation_timestamp" {
  description = "Creation timestamp of the firewall rule"
  value       = google_compute_firewall.firewall_rule.creation_timestamp
} 