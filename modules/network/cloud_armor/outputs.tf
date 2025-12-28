/**
 * Copyright 2023 Ashes
 *
 * Cloud Armor Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the created security policy"
  value       = google_compute_security_policy.policy.id
}

output "self_link" {
  description = "The self_link of the created security policy"
  value       = google_compute_security_policy.policy.self_link
}

output "name" {
  description = "The name of the created security policy"
  value       = google_compute_security_policy.policy.name
}

# Legacy outputs (kept for backwards compatibility)
output "policy_id" {
  description = "The ID of the created security policy (deprecated: use 'id' instead)"
  value       = google_compute_security_policy.policy.id
}

output "policy_name" {
  description = "The name of the created security policy (deprecated: use 'name' instead)"
  value       = google_compute_security_policy.policy.name
}

output "policy_self_link" {
  description = "The self_link of the created security policy (deprecated: use 'self_link' instead)"
  value       = google_compute_security_policy.policy.self_link
}

output "fingerprint" {
  description = "Fingerprint of the security policy"
  value       = google_compute_security_policy.policy.fingerprint
} 