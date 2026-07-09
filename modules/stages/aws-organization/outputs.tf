output "organization_id" {
  description = "The ID of the AWS organization."
  value       = module.organization.organization_id
}

output "management_account_id" {
  description = "The account ID of the organization management (payer) account."
  value       = module.organization.management_account_id
}

output "organization_root_id" {
  description = "The ID of the organization root (r-xxxx), under which the top-level OUs are created. Consumed by the aws-security root as the Security Hub configuration-policy association target."
  value       = module.organization.roots_id
}

output "ou_ids" {
  description = "Map of OU name (or parent/name path for child OUs) to OU ID."
  value       = module.organization.ou_ids
}

output "account_ids" {
  description = "Map of member-account name to account ID."
  value       = { for k, m in module.account : k => m.account_id }
}

output "account_role_arns" {
  description = "Map of member-account name to its cross-account access role ARN."
  value       = { for k, m in module.account : k => m.cross_account_role_arn }
}

output "policy_attachment_ids" {
  description = "Map of guardrail attachment key to the attachment resource ID."
  value       = module.policies.attachment_ids
}
