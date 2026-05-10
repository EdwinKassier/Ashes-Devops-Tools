output "security_policy_id" {
  description = "Resource ID of the Cloud Armor security policy"
  value       = module.cloud_armor.id
}

output "security_policy_self_link" {
  description = "Self-link — attach this to a backend service's security_policy field"
  value       = module.cloud_armor.self_link
}
