output "policy_id" {
  description = "The ID of the Organizations backup policy."
  value       = aws_organizations_policy.backup.id
}

output "policy_arn" {
  description = "The ARN of the Organizations backup policy."
  value       = aws_organizations_policy.backup.arn
}
