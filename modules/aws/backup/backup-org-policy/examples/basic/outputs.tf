output "policy_id" {
  description = "The ID of the Organizations backup policy."
  value       = module.backup_org_policy.policy_id
}

output "policy_arn" {
  description = "The ARN of the Organizations backup policy."
  value       = module.backup_org_policy.policy_arn
}
