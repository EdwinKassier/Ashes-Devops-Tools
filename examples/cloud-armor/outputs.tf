output "security_policy_id" {
  description = "Cloud Armor policy ID — attach to Backend Service security_policy field"
  value       = module.cloud_armor.policy_id
}
