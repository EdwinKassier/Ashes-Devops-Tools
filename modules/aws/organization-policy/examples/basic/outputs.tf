output "policy_ids" {
  description = "Map of policy name to created Organizations policy ID."
  value       = module.organization_policy.policy_ids
}

output "policy_types" {
  description = "Map of policy name to its Organizations policy type."
  value       = module.organization_policy.policy_types
}
