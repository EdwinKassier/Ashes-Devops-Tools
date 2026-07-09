output "organization_id" {
  description = "The ID of the AWS organization."
  value       = module.aws_organization.organization_id
}

output "account_ids" {
  description = "Map of member-account name to account ID."
  value       = module.aws_organization.account_ids
}

output "policy_attachment_ids" {
  description = "Map of guardrail attachment key to the attachment resource ID."
  value       = module.aws_organization.policy_attachment_ids
}
