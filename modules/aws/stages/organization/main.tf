# aws-organization stage
#
# Thin orchestration wrapper composing the AWS control-plane primitives into a
# complete SRA landing-zone organization:
#   - organization              — org, OU topology, enabled policy types, trusted access
#   - account (for_each)         — the foundational + workload member accounts
#   - organization-policy        — the guardrail SCP/RCP/declarative/tag policy set + attachments
#   - iam-organizations-features — centralized root-access management
#
# OU topology, enabled policy types and trusted-service principals use the
# organization module's SRA defaults; callers override accounts and the
# account-qualified carve-out ARNs.

# Organization structure (OUs, enabled policy types, trusted access).
module "organization" {
  source = "../../governance/organization"

  # top_level_ous / child_ous / enabled_policy_types / aws_service_access_principals
  # use the module's SRA foundational defaults.
}

locals {
  # Foundational accounts plus any caller-supplied workload accounts share one
  # for_each so every account is created by the same account module invocation.
  all_accounts = merge(var.accounts, var.workload_accounts)
}

# Member accounts, one per entry in the merged account map.
module "account" {
  source   = "../../governance/account"
  for_each = local.all_accounts

  account_name       = each.key
  email              = each.value.email
  parent_ou_id       = module.organization.ou_ids[each.value.ou]
  alternate_contacts = try(each.value.alternate_contacts, {})
  tags               = try(each.value.tags, {})
}

locals {
  # Guardrail attachments, keyed by stable caller strings (known at plan time)
  # so the organization-policy for_each does not depend on computed OU/root IDs.
  # backup-policy is authored by the policy module but attached later (Epic H).
  attachments = {
    "deny-tamper@root"        = { policy_key = "scp-deny-tamper", target_id = module.organization.roots_id }
    "region-restriction@root" = { policy_key = "scp-region-restriction", target_id = module.organization.roots_id }
    "baseline@root"           = { policy_key = "scp-baseline", target_id = module.organization.roots_id }
    "data-perimeter@root"     = { policy_key = "rcp-data-perimeter", target_id = module.organization.roots_id }
    "declarative@workloads"   = { policy_key = "declarative-ec2", target_id = module.organization.ou_ids["Workloads"] }
    "tag-policy@root"         = { policy_key = "tag-policy", target_id = module.organization.roots_id }
  }
}

# Guardrail policy set (SCPs, RCP, declarative EC2, tag policy) and attachments.
module "policies" {
  source = "../../governance/organization-policy"

  org_id                  = module.organization.organization_id
  allowed_regions         = var.allowed_regions
  terraform_run_role_arn  = var.terraform_run_role_arn
  break_glass_role_arn    = var.break_glass_role_arn
  log_archive_bucket_name = var.log_archive_bucket_name
  attachments             = local.attachments

  # Member-account carve-outs + perimeter tuning (validated in the policy module).
  pipeline_role_names                = var.pipeline_role_names
  break_glass_role_names             = var.break_glass_role_names
  data_perimeter_trusted_account_ids = var.data_perimeter_trusted_account_ids
  allow_vpc_bpa_exclusions           = var.allow_vpc_bpa_exclusions
}

# Centralized root-access management for the organization.
module "root_access" {
  source = "../../governance/iam-organizations-features"
}

# Management-account-scoped cost governance: budgets, Cost Anomaly Detection and
# cost-allocation-tag activation. Consolidated billing rolls all member-account
# spend up to the payer, so this is organization-wide only from the management
# account — which is this stage's default provider.
module "cost_governance" {
  source = "../../governance/cost-governance"

  enable_cost_governance  = var.enable_cost_governance
  budgets                 = var.budgets
  cost_allocation_tags    = var.cost_allocation_tags
  notifications_topic_arn = var.cost_notifications_topic_arn
  anomaly_email           = var.cost_anomaly_email
}

# Member-account TFC workload identity (OIDC provider + tfc-plan / tfc-apply),
# deployed by a SERVICE_MANAGED StackSet from this management-account stage to
# the OUs of the bound accounts. Auto-deployment gives accounts that join those
# OUs the OIDC provider; their roles appear once they are added to
# tfc_workspace_bindings. Requires CloudFormation StackSets trusted access
# (member.org.stacksets.cloudformation.amazonaws.com — in the organization
# module's default aws_service_access_principals).
module "tfc_oidc_baseline" {
  source = "../../iam/tfc-oidc-baseline"
  count  = var.enable_tfc_oidc_baseline ? 1 : 0

  tfc_hostname              = var.tfc_hostname
  tfc_organization          = var.tfc_organization
  tfc_project               = var.tfc_project
  allow_workspace_wildcards = var.tfc_oidc_allow_workspace_wildcards
  apply_role_policy_arns    = var.tfc_apply_role_policy_arns

  # Permissions boundary on tfc-apply (default: embedded tfc-apply-boundary).
  enable_apply_permissions_boundary = var.tfc_enable_apply_permissions_boundary
  apply_permissions_boundary_arn    = var.tfc_apply_permissions_boundary_arn
  enable_apply_boundary_propagation = var.tfc_enable_apply_boundary_propagation
  call_as                           = var.tfc_oidc_call_as

  # Plan-role data-plane read deny (ReadOnlyAccess minus GetObject/GetSecretValue/...).
  enable_plan_role_data_read_deny = var.tfc_enable_plan_role_data_read_deny
  plan_role_data_read_exempt_arns = var.tfc_plan_role_data_read_exempt_arns

  account_bindings = {
    for k, b in var.tfc_workspace_bindings : k => {
      account_id = module.account[k].account_id
      workspaces = b.workspaces
      project    = b.project
    }
  }

  # Keyed by OU name (plan-known) so the per-OU stack instances are stable.
  target_ou_ids = {
    for ou in distinct([for k in keys(var.tfc_workspace_bindings) : local.all_accounts[k].ou]) :
    ou => module.organization.ou_ids[ou]
  }

  # Trusted access for StackSets is enabled by module.organization.
  depends_on = [module.organization]
}
