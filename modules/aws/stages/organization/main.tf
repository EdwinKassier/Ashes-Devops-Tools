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

  account_name       = coalesce(try(each.value.name, null), each.key)
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
  default_attachments = merge(
    local.attachments,
    {
      "declarative-baseline@root" = { policy_key = "declarative-ec2-baseline", target_id = module.organization.roots_id }
      "aiservices-opt-out@root"   = { policy_key = "aiservices-opt-out", target_id = module.organization.roots_id }
    },
  )
  # Attachments of disabled built-in policies are dropped with them.
  effective_attachments = merge(
    { for k, a in local.default_attachments : k => a if !contains(var.disabled_org_policies, a.policy_key) },
    var.org_policy_attachments,
  )
}

locals {
  # Member-account break-glass name: the first explicit break_glass_role_names
  # entry, else the name part of break_glass_role_arn — exactly what the
  # deny-tamper SCP renders as arn:aws:iam::*:role/<name>.
  member_break_glass_role_name = length(var.break_glass_role_names) > 0 ? var.break_glass_role_names[0] : regex("role/(.+)$", var.break_glass_role_arn)[0]

  # Default trust: the management-account break-glass role itself.
  member_break_glass_trusted_principal_arns = length(var.member_break_glass_trusted_principal_arns) > 0 ? var.member_break_glass_trusted_principal_arns : [var.break_glass_role_arn]
}

# Guardrail policy set (SCPs, RCP, declarative EC2, tag policy) and attachments.
module "policies" {
  source = "../../governance/organization-policy"

  org_id                  = module.organization.organization_id
  allowed_regions         = var.allowed_regions
  terraform_run_role_arn  = var.terraform_run_role_arn
  break_glass_role_arn    = var.break_glass_role_arn
  log_archive_bucket_name = var.log_archive_bucket_name
  attachments             = local.effective_attachments
  policy_overrides        = var.org_policy_overrides
  disabled_policies       = var.disabled_org_policies

  # Member-account carve-outs + perimeter tuning (validated in the policy module).
  pipeline_role_names                = var.pipeline_role_names
  break_glass_role_names             = var.break_glass_role_names
  data_perimeter_trusted_account_ids = var.data_perimeter_trusted_account_ids
  allow_vpc_bpa_exclusions           = var.allow_vpc_bpa_exclusions

  # Detection settings are reachable only from the security accounts' pipeline.
  central_detection_account_ids = [for k in var.central_detection_account_keys : module.account[k].account_id]

  # Web-identity tenant pins (RCP): TFC tokens only from this org's TFC
  # organization, GitHub tokens only from the listed owners.
  federation_tenant_pins = {
    tfc_hostname     = var.tfc_hostname
    tfc_organization = var.pin_tfc_federation_to_org ? var.tfc_organization : null
    github_owners    = var.github_federation_owners
    github_owner_ids = var.github_federation_owner_ids
    # Built-in IdPs (Cognito, Google, Facebook, Amazon) need no IAM provider
    # resource, so only the RCP can stop a role trusting an attacker's pool.
    allowed_builtin_providers = var.allowed_builtin_web_identity_providers
  }
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

  # Privileged-role protection in the tfc-apply boundary + the member-account
  # break-glass role (sibling StackSet, every member account via the org root).
  # The name is the SAME one the deny-tamper SCP exempts, so it is occupied —
  # and only break-glass / the StackSet execution role can modify it.
  break_glass_role_name                     = local.member_break_glass_role_name
  enable_member_break_glass_role            = var.enable_member_break_glass_role
  member_break_glass_trusted_principal_arns = local.member_break_glass_trusted_principal_arns
  member_break_glass_require_mfa            = var.member_break_glass_require_mfa
  member_break_glass_target_ou_ids          = { root = module.organization.roots_id }

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

# Least-privilege management-account roles, one plan/apply pair per
# management-default workspace (aws-security, aws-backup), so those roots no
# longer share the phase-0 management admin role. aws-organization itself keeps
# the phase-0 role.
module "tfc_management_roles" {
  source = "../../iam/tfc-management-roles"
  count  = var.enable_tfc_management_roles && var.tfc_organization != null ? 1 : 0

  tfc_organization = var.tfc_organization
  tfc_hostname     = var.tfc_hostname
  tfc_project      = var.tfc_project
  workspaces       = var.tfc_management_workspaces
}

# The baseline StackSet puts a GitHub OIDC provider in every targeted account.
# Unpinned, any admin there can make a role trust repo:<anyone>/*.
check "github_federation_pinned" {
  assert {
    condition     = !var.enable_tfc_oidc_baseline || length(var.github_federation_owners) + length(var.github_federation_owner_ids) > 0
    error_message = "The TFC OIDC baseline deploys a GitHub Actions OIDC provider to member accounts, but github_federation_owners / github_federation_owner_ids is empty, so GitHub federation is unpinned org-wide. Set aws.github_federation_owners in config/landing-zone.yaml."
  }
}
