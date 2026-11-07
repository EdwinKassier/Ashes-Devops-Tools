# Cross-root contract (Convention 4). These keys are consumed by downstream aws
# roots via terraform_remote_state. Keep them stable across refactors — renaming
# a key breaks every root that reads it.

locals {
  # The aws-organization cross-root contract: ONE non-sensitive object that downstream
  # roots read as .outputs.contract (tfc-admin: tfe_outputs nonsensitive_values
  # .contract). Never put a sensitive value in it: one sensitive attribute moves
  # the whole object into tfe_outputs' sensitive_values. Keys are stable;
  # scripts/check-contracts.sh enforces the read side.
  contract = {
    organization_id                = module.aws_organization.organization_id
    management_account_id          = module.aws_organization.management_account_id
    organization_root_id           = module.aws_organization.organization_root_id
    ou_ids                         = module.aws_organization.ou_ids
    account_ids                    = module.aws_organization.account_ids
    account_role_arns              = module.aws_organization.account_role_arns
    tfc_plan_role_arns             = module.aws_organization.tfc_plan_role_arns
    tfc_apply_role_arns            = module.aws_organization.tfc_apply_role_arns
    tfc_workspace_bindings         = module.aws_organization.tfc_workspace_bindings
    tfc_management_plan_role_arns  = module.aws_organization.tfc_management_plan_role_arns
    tfc_management_apply_role_arns = module.aws_organization.tfc_management_apply_role_arns
    guard_alerts_topic_arn         = module.aws_organization.guard_alerts_topic_arn
  }
}

output "contract" {
  description = "The aws-organization cross-root contract: every key below in one non-sensitive object. Downstream roots read this output only; the individual outputs are deprecated aliases kept until v1.0."
  value       = local.contract
}

output "organization_id" {
  description = "Deprecated: read contract.organization_id (removed in v1.0). The ID of the AWS organization."
  value       = local.contract.organization_id
}

output "management_account_id" {
  description = "Deprecated: read contract.management_account_id (removed in v1.0). The account ID of the organization management (payer) account."
  value       = local.contract.management_account_id
}

output "organization_root_id" {
  description = "Deprecated: read contract.organization_root_id (removed in v1.0). The organization root ID (r-xxxx). Consumed by the aws-security root as the Security Hub configuration-policy association target."
  value       = local.contract.organization_root_id
}

output "ou_ids" {
  description = "Deprecated: read contract.ou_ids (removed in v1.0). Map of OU name (or parent/name path for child OUs) to OU ID."
  value       = local.contract.ou_ids
}

output "account_ids" {
  description = "Deprecated: read contract.account_ids (removed in v1.0). Map of member-account name to account ID."
  value       = local.contract.account_ids
}

output "account_role_arns" {
  description = "Deprecated: read contract.account_role_arns (removed in v1.0). Map of member-account name to its cross-account access role ARN, consumed by downstream aws roots."
  value       = local.contract.account_role_arns
}

# Member-account TFC dynamic-credential roles, keyed by account key. Set on each
# downstream workspace bound to that account (tfc_workspace_bindings):
#   TFC_AWS_PROVIDER_AUTH  = true
#   TFC_AWS_PLAN_ROLE_ARN  = tfc_plan_role_arns[<account key>]
#   TFC_AWS_APPLY_ROLE_ARN = tfc_apply_role_arns[<account key>]
output "tfc_plan_role_arns" {
  description = "Deprecated: read contract.tfc_plan_role_arns (removed in v1.0). Map of account key -> member-account tfc-plan (read-only) role ARN, for TFC_AWS_PLAN_ROLE_ARN. Empty when the TFC OIDC baseline is disabled."
  value       = local.contract.tfc_plan_role_arns
}

output "tfc_apply_role_arns" {
  description = "Deprecated: read contract.tfc_apply_role_arns (removed in v1.0). Map of account key -> member-account tfc-apply role ARN, for TFC_AWS_APPLY_ROLE_ARN. Empty when the TFC OIDC baseline is disabled."
  value       = local.contract.tfc_apply_role_arns
}

output "tfc_workspace_bindings" {
  description = "Deprecated: read contract.tfc_workspace_bindings (removed in v1.0). Map of account key -> TFC workspace names bound to that account's tfc-plan / tfc-apply roles."
  value       = local.contract.tfc_workspace_bindings
}

# Dedicated least-privilege management-account roles per management-default
# workspace; tfc-admin (aws_organization_outputs_from_tfc) binds them in place
# of the shared phase-0 management role.
output "tfc_management_plan_role_arns" {
  description = "Deprecated: read contract.tfc_management_plan_role_arns (removed in v1.0). Workspace name -> dedicated management-account PLAN role ARN (aws-security, aws-backup)."
  value       = local.contract.tfc_management_plan_role_arns
}

output "tfc_management_apply_role_arns" {
  description = "Deprecated: read contract.tfc_management_apply_role_arns (removed in v1.0). Workspace name -> dedicated management-account APPLY role ARN (aws-security, aws-backup)."
  value       = local.contract.tfc_management_apply_role_arns
}

output "guard_alerts_topic_arn" {
  description = "Deprecated: read contract.guard_alerts_topic_arn (removed in v1.0). ARN of the org-guard-alerts SNS topic (us-east-1, management account): org-detection teardown and organization-trail tampering alerts."
  value       = local.contract.guard_alerts_topic_arn
}
