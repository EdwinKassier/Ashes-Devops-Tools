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

output "organization_root_id" {
  description = "The organization root ID (r-xxxx). Consumed by the aws-security root as the Security Hub configuration-policy association target."
  value       = module.aws_organization.organization_root_id
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

# Member-account TFC dynamic-credential roles, keyed by account key. Set on each
# downstream workspace bound to that account (tfc_workspace_bindings):
#   TFC_AWS_PROVIDER_AUTH  = true
#   TFC_AWS_PLAN_ROLE_ARN  = tfc_plan_role_arns[<account key>]
#   TFC_AWS_APPLY_ROLE_ARN = tfc_apply_role_arns[<account key>]
output "tfc_plan_role_arns" {
  description = "Map of account key -> member-account tfc-plan (read-only) role ARN, for TFC_AWS_PLAN_ROLE_ARN. Empty when the TFC OIDC baseline is disabled."
  value       = module.aws_organization.tfc_plan_role_arns
}

output "tfc_apply_role_arns" {
  description = "Map of account key -> member-account tfc-apply role ARN, for TFC_AWS_APPLY_ROLE_ARN. Empty when the TFC OIDC baseline is disabled."
  value       = module.aws_organization.tfc_apply_role_arns
}

output "tfc_workspace_bindings" {
  description = "Map of account key -> TFC workspace names bound to that account's tfc-plan / tfc-apply roles."
  value       = module.aws_organization.tfc_workspace_bindings
}

# Dedicated least-privilege management-account roles per management-default
# workspace; tfc-admin (aws_organization_outputs_from_tfc) binds them in place
# of the shared phase-0 management role.
output "tfc_management_plan_role_arns" {
  description = "Workspace name -> dedicated management-account PLAN role ARN (aws-security, aws-backup)."
  value       = module.aws_organization.tfc_management_plan_role_arns
}

output "tfc_management_apply_role_arns" {
  description = "Workspace name -> dedicated management-account APPLY role ARN (aws-security, aws-backup)."
  value       = module.aws_organization.tfc_management_apply_role_arns
}
