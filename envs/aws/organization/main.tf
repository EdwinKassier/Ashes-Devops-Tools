# Phase-1 of the two-phase bootstrap. Composes the aws-organization stage in the
# management account: creates the org + SRA OU tree, vends the foundational
# member accounts, attaches the guardrail policies (SCP / RCP / declarative /
# tag), and centralizes root-access management. This root is the PRODUCER of the
# cross-root contract (organization_id, account_role_arns, ...) — it has no
# terraform_remote_state data source, so it validates credential-free.
module "aws_organization" {
  source = "../../../modules/aws/stages/organization"

  accounts                = local.accounts
  workload_accounts       = local.workload_accounts
  allowed_regions         = local.allowed_regions
  terraform_run_role_arn  = local.terraform_run_role_arn
  break_glass_role_arn    = local.break_glass_role_arn
  log_archive_bucket_name = local.log_archive_bucket_name

  # Cost governance (management-account-scoped).
  enable_cost_governance       = var.enable_cost_governance
  budgets                      = var.budgets
  cost_allocation_tags         = var.cost_allocation_tags
  cost_notifications_topic_arn = var.cost_notifications_topic_arn
  cost_anomaly_email           = var.cost_anomaly_email

  # Member-account TFC workload identity (OIDC provider + tfc-plan / tfc-apply).
  enable_tfc_oidc_baseline              = var.enable_tfc_oidc_baseline
  tfc_organization                      = local.tfc_organization
  tfc_hostname                          = var.tfc_hostname
  pin_tfc_federation_to_org             = var.pin_tfc_federation_to_org
  enable_tfc_management_roles           = var.enable_tfc_management_roles
  org_policy_overrides                  = var.org_policy_overrides
  disabled_org_policies                 = var.disabled_org_policies
  org_policy_attachments                = var.org_policy_attachments
  github_federation_owners              = local.github_federation_owners
  tfc_project                           = local.tfc_project
  tfc_workspace_bindings                = local.tfc_workspace_bindings
  tfc_oidc_allow_workspace_wildcards    = var.tfc_oidc_allow_workspace_wildcards
  tfc_apply_role_policy_arns            = var.tfc_apply_role_policy_arns
  tfc_enable_apply_permissions_boundary = var.tfc_enable_apply_permissions_boundary
  tfc_apply_permissions_boundary_arn    = var.tfc_apply_permissions_boundary_arn

  # Member-account break-glass role (occupies the SCP-exempt break-glass name in
  # every member account; trusts the management break-glass principal + MFA).
  enable_member_break_glass_role            = var.enable_member_break_glass_role
  member_break_glass_trusted_principal_arns = var.member_break_glass_trusted_principal_arns
  member_break_glass_require_mfa            = var.member_break_glass_require_mfa

  # VPC Block Public Access exclusions: required only for aws-workload
  # app_ingress_mode = "public_alb" (internet-facing ALB). Off by default.
  allow_vpc_bpa_exclusions = var.allow_vpc_bpa_exclusions
}
