/**
 * Copyright 2023 Ashes
 *
 * Hierarchical Firewall Policy Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the hierarchical firewall policy"
  value       = google_compute_firewall_policy.policy.id
}

output "self_link" {
  description = "The self_link of the hierarchical firewall policy"
  value       = google_compute_firewall_policy.policy.self_link
}

output "name" {
  description = "The name of the hierarchical firewall policy"
  value       = google_compute_firewall_policy.policy.name
}

output "policy" {
  description = "The full firewall policy resource"
  value       = google_compute_firewall_policy.policy
}

output "rules" {
  description = "Map of created firewall policy rules"
  value       = google_compute_firewall_policy_rule.rules
}

output "associations" {
  description = "Map of created policy associations"
  value       = google_compute_firewall_policy_association.associations
}

output "fingerprint" {
  description = "Fingerprint of the firewall policy"
  value       = google_compute_firewall_policy.policy.fingerprint
}

output "rule_tuple_count" {
  description = "Total count of rule tuples in this policy"
  value       = google_compute_firewall_policy.policy.rule_tuple_count
}
