output "policy_id" {
  description = "The ID of the created security policy"
  value       = google_compute_security_policy.policy.id
}

output "policy_name" {
  description = "The name of the created security policy"
  value       = google_compute_security_policy.policy.name
}

output "policy_self_link" {
  description = "The self_link of the created security policy"
  value       = google_compute_security_policy.policy.self_link
}

output "fingerprint" {
  description = "Fingerprint of the security policy"
  value       = google_compute_security_policy.policy.fingerprint
} 