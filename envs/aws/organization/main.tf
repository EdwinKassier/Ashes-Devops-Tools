# Phase-1 of the two-phase bootstrap. Composes the aws-organization stage in the
# management account: creates the org + SRA OU tree, vends the foundational
# member accounts, attaches the guardrail policies (SCP / RCP / declarative /
# tag), and centralizes root-access management. This root is the PRODUCER of the
# cross-root contract (organization_id, account_role_arns, ...) — it has no
# terraform_remote_state data source, so it validates credential-free.
module "aws_organization" {
  source = "../../../modules/aws/stages/organization"

  accounts                = var.accounts
  workload_accounts       = var.workload_accounts
  allowed_regions         = var.allowed_regions
  terraform_run_role_arn  = var.terraform_run_role_arn
  break_glass_role_arn    = var.break_glass_role_arn
  log_archive_bucket_name = var.log_archive_bucket_name

  # Cost governance (management-account-scoped).
  enable_cost_governance       = var.enable_cost_governance
  budgets                      = var.budgets
  cost_allocation_tags         = var.cost_allocation_tags
  cost_notifications_topic_arn = var.cost_notifications_topic_arn
  cost_anomaly_email           = var.cost_anomaly_email

  # Member-account TFC workload identity (OIDC provider + tfc-plan / tfc-apply).
  enable_tfc_oidc_baseline           = var.enable_tfc_oidc_baseline
  tfc_organization                   = var.tfc_organization
  tfc_hostname                       = var.tfc_hostname
  tfc_project                        = var.tfc_project
  tfc_workspace_bindings             = var.tfc_workspace_bindings
  tfc_oidc_allow_workspace_wildcards = var.tfc_oidc_allow_workspace_wildcards
  tfc_apply_role_policy_arns         = var.tfc_apply_role_policy_arns
}
