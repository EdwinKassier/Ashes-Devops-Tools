output "policy_ids" {
  description = "Map of policy name to created Organizations policy ID."
  value       = { for name, p in aws_organizations_policy.policy : name => p.id }
}

output "policy_arns" {
  description = "Map of policy name to created Organizations policy ARN."
  value       = { for name, p in aws_organizations_policy.policy : name => p.arn }
}

output "policy_types" {
  description = "Map of policy name to its Organizations policy type."
  value       = { for name, p in aws_organizations_policy.policy : name => p.type }
}

output "attachment_ids" {
  description = "Map of caller attachment key to the attachment resource ID."
  value       = { for key, a in aws_organizations_policy_attachment.attach : key => a.id }
}
