# Cross-root contract (Convention 4). These keys are consumed by downstream aws
# roots via terraform_remote_state. Keep them stable across refactors — renaming
# a key breaks every root that reads it.

output "organization_id" {
  description = "The ID of the AWS organization."
  value       = module.aws_organization.organization_id
}

output "management_account_id" {
  description = "The account ID of the organization management (payer) account."
  value       = module.aws_organization.management_account_id
}

output "ou_ids" {
  description = "Map of OU name (or parent/name path for child OUs) to OU ID."
  value       = module.aws_organization.ou_ids
}

output "account_ids" {
  description = "Map of member-account name to account ID."
  value       = module.aws_organization.account_ids
}

output "account_role_arns" {
  description = "Map of member-account name to its cross-account access role ARN, consumed by downstream aws roots."
  value       = module.aws_organization.account_role_arns
}
