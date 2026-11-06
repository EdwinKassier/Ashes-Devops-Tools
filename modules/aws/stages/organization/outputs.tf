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

output "cost_budget_ids" {
  description = "Map of budget name to budget resource ID created by the cost-governance module. Empty when cost governance is disabled."
  value       = module.cost_governance.budget_ids
}

output "tfc_plan_role_arns" {
  description = "Map of account key -> member-account tfc-plan (read-only) role ARN. Set as TFC_AWS_PLAN_ROLE_ARN on the workspaces bound to that account. Empty when the TFC OIDC baseline is disabled."
  value       = var.enable_tfc_oidc_baseline ? module.tfc_oidc_baseline[0].plan_role_arns : {}
}

output "tfc_apply_role_arns" {
  description = "Map of account key -> member-account tfc-apply role ARN. Set as TFC_AWS_APPLY_ROLE_ARN on the workspaces bound to that account. Empty when the TFC OIDC baseline is disabled."
  value       = var.enable_tfc_oidc_baseline ? module.tfc_oidc_baseline[0].apply_role_arns : {}
}

output "tfc_workspace_bindings" {
  description = "Map of account key -> TFC workspace names bound to that account's tfc-plan / tfc-apply roles (empty when the baseline is disabled)."
  value       = var.enable_tfc_oidc_baseline ? { for k, b in var.tfc_workspace_bindings : k => b.workspaces } : {}
}

output "tfc_oidc_stack_set_name" {
  description = "Name of the StackSet deploying the TFC OIDC baseline, or null when disabled."
  value       = var.enable_tfc_oidc_baseline ? module.tfc_oidc_baseline[0].stack_set_name : null
}

output "member_break_glass_stack_set_name" {
  description = "Name of the StackSet deploying the break-glass role into member accounts, or null when disabled."
  value       = var.enable_tfc_oidc_baseline ? module.tfc_oidc_baseline[0].member_break_glass_stack_set_name : null
}

output "tfc_management_plan_role_arns" {
  description = "Workspace name -> dedicated management-account PLAN role ARN (aws-security, aws-backup). Empty when enable_tfc_management_roles is false."
  value       = try(module.tfc_management_roles[0].plan_role_arns, {})
}

output "tfc_management_apply_role_arns" {
  description = "Workspace name -> dedicated management-account APPLY role ARN. Empty when enable_tfc_management_roles is false."
  value       = try(module.tfc_management_roles[0].apply_role_arns, {})
}

output "org_trail_cloudwatch_role_arn" {
  description = "ARN of the organization trail's CloudWatch Logs delivery role (null when create_org_trail_delivery_role is false)."
  value       = try(aws_iam_role.org_trail_cloudwatch[0].arn, null)
}

output "guard_alerts_topic_arn" {
  description = "ARN of the org-guard-alerts SNS topic (us-east-1, management account): org-detection teardown and organization-trail tampering alerts."
  value       = aws_sns_topic.guard_alerts.arn
}
