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
  source = "../../aws/organization"

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
  source   = "../../aws/account"
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
  source = "../../aws/organization-policy"

  org_id                  = module.organization.organization_id
  allowed_regions         = var.allowed_regions
  management_account_id   = module.organization.management_account_id
  security_account_id     = module.account["security_tooling"].account_id
  terraform_run_role_arn  = var.terraform_run_role_arn
  break_glass_role_arn    = var.break_glass_role_arn
  log_archive_bucket_name = var.log_archive_bucket_name
  attachments             = local.attachments
}

# Centralized root-access management for the organization.
module "root_access" {
  source = "../../aws/iam-organizations-features"
}

# Management-account-scoped cost governance: budgets, Cost Anomaly Detection and
# cost-allocation-tag activation. Consolidated billing rolls all member-account
# spend up to the payer, so this is organization-wide only from the management
# account — which is this stage's default provider.
module "cost_governance" {
  source = "../../aws/cost-governance"

  enable_cost_governance  = var.enable_cost_governance
  budgets                 = var.budgets
  cost_allocation_tags    = var.cost_allocation_tags
  notifications_topic_arn = var.cost_notifications_topic_arn
  anomaly_email           = var.cost_anomaly_email
}
