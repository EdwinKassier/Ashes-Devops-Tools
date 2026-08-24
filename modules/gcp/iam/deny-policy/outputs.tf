output "deny_policy_ids" {
  description = "Map of deny-policy name to the created google_iam_deny_policy resource ID."
  value       = { for k, v in google_iam_deny_policy.this : k => v.id }
}

output "deny_policy_names" {
  description = "List of deny-policy names created."
  value       = keys(google_iam_deny_policy.this)
}
