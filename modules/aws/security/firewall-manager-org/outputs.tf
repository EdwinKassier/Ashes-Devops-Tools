output "admin_account_id" {
  description = "The account ID registered as the Firewall Manager administrator, or null when Firewall Manager is disabled."
  value       = try(aws_fms_admin_account.this[0].account_id, null)
}

output "policy_ids" {
  description = "Map of FMS policy name to policy ID for every policy created by this module."
  value       = { for name, policy in aws_fms_policy.this : name => policy.id }
}
