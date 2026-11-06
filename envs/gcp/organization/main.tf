locals {
  shared_environment = {
    display_name            = "Shared Services"
    description             = "Shared platform services"
    iam_group_role_bindings = var.shared_iam_group_role_bindings
    is_production           = false
  }

  organization_units = merge(
    {
      shared = local.shared_environment
    },
    {
      for env_key, env in local.environments : env_key => {
        display_name            = env.display_name
        description             = "${env.display_name} environment"
        iam_group_role_bindings = env.iam_group_role_bindings
        is_production           = env.is_production
      }
    }
  )

  # Outputs from the gcp-bootstrap root (admin project, Terraform admin SA, WIF
  # pools). gcp-bootstrap is applied first; this root reads it via remote state
  # (audit H3 — control-plane state decomposition).
  bootstrap = data.terraform_remote_state.gcp_bootstrap.outputs
}

# 1. Organization: Hierarchy & Governance
module "organization" {
  source = "../../../modules/gcp/stages/organization"

  domain               = local.domain
  org_id               = data.google_organization.org.org_id
  customer_id          = data.google_organization.org.directory_customer_id
  admin_project_id     = local.bootstrap.admin_project_id
  admin_project_number = local.bootstrap.admin_project_number
  billing_account      = data.google_billing_account.billing.id
  project_prefix       = local.project_prefix
  environments         = local.organization_units

  admin_email                      = local.admin_email
  break_glass_user                 = var.break_glass_user
  terraform_admin_email            = local.bootstrap.terraform_admin_email
  enable_legacy_admin_folder_roles = var.enable_legacy_admin_folder_roles
  organization_admin_groups        = local.organization_admin_groups
  billing_admin_groups             = local.billing_admin_groups

  # Standing admin is group-only; user principals only via the escape hatch.
  allow_user_principals_for_break_glass = var.allow_user_principals_for_break_glass

  # Just-in-time org admin (Privileged Access Manager), opt-in.
  enable_pam               = var.enable_pam
  pam_eligible_groups      = var.pam_eligible_groups
  pam_approver_groups      = var.pam_approver_groups
  pam_max_request_duration = var.pam_max_request_duration

  # Per-environment folder-scoped VPC-SC access policies; each environment's
  # workload SAs get rights on their own policy only. try() keeps an older
  # gcp-bootstrap state (no such outputs) planning with no grants.
  enable_scoped_access_policies = var.enable_scoped_access_policies
  workload_service_accounts = {
    for env, sas in try(local.bootstrap.workload_service_accounts, {}) : env => sas
    if contains(keys(local.environments), env)
  }

  # projects-apply delegated folder IAM, bound on each environment folder and the
  # shared folder (not the org node).
  projects_apply_service_account  = try(local.bootstrap.stage_service_accounts["projects"].apply, null)
  delegated_workload_folder_roles = try(local.bootstrap.delegated_workload_folder_roles, [])
  delegated_network_folder_roles  = try(local.bootstrap.delegated_network_folder_roles, [])

  default_region                        = local.default_region
  allowed_regions                       = local.allowed_regions
  strict_folder_policy_environment_keys = var.strict_folder_policy_environment_keys
  enforce_os_login                      = var.enforce_os_login
  os_login_exempt_environment_keys      = var.os_login_exempt_environment_keys
  security_contact_email                = var.security_contact_email
  billing_contact_email                 = var.billing_contact_email
  monthly_budget_amount                 = var.monthly_budget_amount
  budget_currency                       = var.budget_currency

  # Dedicated logging project for the org audit sink, bucket, audit
  # CMEK and control-plane alerts (default null = admin project).
  logging_project_id     = var.logging_project_id
  logging_project_number = var.logging_project_number

  # Soft delete on the audit buckets (Object Versioning is always on unless
  # the WORM lock is enabled, which GCS does not allow together with versioning).
  audit_soft_delete_retention_days = var.audit_soft_delete_retention_days

  # Control-plane alerting (on by default).
  enable_control_plane_alerting = var.enable_control_plane_alerting
  alert_notification_emails     = var.alert_notification_emails
  alert_notification_channels   = var.alert_notification_channels
  break_glass_principal_emails  = var.break_glass_principal_emails
  enable_cis_log_metrics        = var.enable_cis_log_metrics

  # Opt-in custom org-policy constraints (default [] = none).
  custom_org_constraints = var.custom_org_constraints

  # Opt-in WORM lock on the audit-log bucket (default false; irreversible).
  enable_audit_bucket_lock = var.enable_audit_bucket_lock

  # Opt-in IAM deny policies at the org node (default [] = none).
  iam_deny_policies = var.iam_deny_policies

  # Opt-in org-wide CMEK enforcement (default off). The prod-hardening
  # preset turns this on.
  enable_cmek_org_policy = var.enable_cmek_org_policy
  cmek_required_services = var.cmek_required_services

  # Opt-in containment of the automation identity (default off; the prod preset
  # turns it on, and a check warns when an is_production environment lacks it). Set containment_exempt_principals to your break-glass
  # principal when enabling — placeholders are rejected.
  enable_admin_containment      = var.enable_admin_containment
  containment_exempt_principals = var.containment_exempt_principals
}

# The projects stage (gcp-projects) and network-hub stage (gcp-network-hub) were
# split into their own roots and states (audit H3). gcp-projects reads this
# root's folders/tag values; gcp-network-hub reads gcp-projects' host project
# IDs. See docs/architecture/gcp-state-decomposition.md.
