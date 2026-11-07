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
  #.
  # Remote state when read (count = 1), else the supplied contract.
  # Each upstream is read through its single `contract` output. A producer
  # state from before that output existed (N-1, not yet re-applied) exposes the
  # same keys as individual outputs, so the read falls back to them; that
  # fallback goes at v1.0 with the individual outputs (UPGRADING.md).
  bootstrap = try(data.terraform_remote_state.gcp_bootstrap[0].outputs.contract, data.terraform_remote_state.gcp_bootstrap[0].outputs, local.bootstrap_contract)

  # Deny-policy ownership follows gcp-bootstrap unless set explicitly; an older
  # bootstrap state without the output means the legacy single-owner model.
  guardrail_owner_mode = coalesce(var.guardrail_owner_mode, try(local.bootstrap.guardrail_owner_mode, null), "organization")
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
  restrict_cloud_run_ingress       = var.restrict_cloud_run_ingress
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
  monthly_budget_amount                 = local.monthly_budget_amount
  budget_threshold_rules                = local.budget_threshold_rules
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
  alert_notification_emails     = local.alert_notification_emails
  budget_notify_alert_channels  = local.notify_budget_channels
  alert_notification_channels   = var.alert_notification_channels
  break_glass_principal_emails  = var.break_glass_principal_emails
  enable_cis_log_metrics        = var.enable_cis_log_metrics

  # Opt-in custom org-policy constraints (default [] = none).
  custom_org_constraints = var.custom_org_constraints

  # Opt-in WORM lock on the audit-log bucket (default false; irreversible).
  enable_audit_bucket_lock = local.enable_audit_bucket_lock

  # Opt-in IAM deny policies at the org node (default [] = none). Legacy
  # organization mode only; in separate mode gcp-guardrails owns them.
  iam_deny_policies = var.iam_deny_policies

  # Opt-in org-wide CMEK enforcement (default off). The prod-hardening
  # preset turns this on.
  enable_cmek_org_policy = var.enable_cmek_org_policy
  cmek_required_services = var.cmek_required_services

  # Opt-in containment of the automation identity (default off; the prod preset
  # turns it on, and a check warns when an is_production environment lacks it). Set containment_exempt_principals to your break-glass
  # principal when enabling — placeholders are rejected.
  org_policy_overrides                   = var.org_policy_overrides
  allowed_workload_identity_issuers      = coalesce(var.allowed_workload_identity_issuers, ["https://${var.tfc_hostname}", "https://token.actions.githubusercontent.com"])
  allowed_workload_identity_aws_accounts = var.allowed_workload_identity_aws_accounts
  wif_tenant_pin_enforcement             = var.wif_tenant_pin_enforcement
  wif_tenant_pins = {
    tfc_hostname     = var.tfc_hostname
    tfc_organization = var.pin_wif_to_tfc_organization ? local.tfc_organization : null
    github_owner_ids = var.wif_github_owner_ids
  }

  # Without a break-glass principal the stage is never asked for containment
  # (it would deny everyone); output.admin_containment_enabled fails the plan.
  enable_admin_containment      = local.enable_admin_containment && length(local.containment_exempt_principals) > 0
  containment_exempt_principals = local.containment_exempt_principals
  # Explicit opt-out (variable or gcp.admin_containment: false in config; unset is not a waiver), or the root's own precondition already fails the plan.
  production_containment_waived = var.enable_admin_containment == false || local.cfg.admin_containment == false || (local.enable_admin_containment && length(local.containment_exempt_principals) == 0)

  # Deny policies are authored and applied by gcp-guardrails (separate) or here
  # (legacy organization mode).
  guardrail_owner_mode = local.guardrail_owner_mode

  # Managed org-policy constraints where Google offers a successor.
  prefer_managed_constraints = var.prefer_managed_constraints

  # Log Analytics bucket + linked BigQuery dataset for the org audit logs.
  enable_log_analytics         = var.enable_log_analytics
  log_analytics_retention_days = var.log_analytics_retention_days

  # Org logging settings (default log-bucket location / CMEK), opt-in.
  enable_logging_organization_settings = var.enable_logging_organization_settings
  logging_settings_kms_key_name        = var.logging_settings_kms_key_name

  # Principal access boundary for the automation SAs, opt-in.
  enable_principal_access_boundary            = local.enable_principal_access_boundary
  principal_access_boundary_allowed_resources = var.principal_access_boundary_allowed_resources
}

# The projects stage (gcp-projects) and network-hub stage (gcp-network-hub) were
# split into their own roots and states. gcp-projects reads this
# root's folders/tag values; gcp-network-hub reads gcp-projects' host project
# IDs. See docs/architecture/gcp-state-decomposition.md.

# The starter profile must have a budget: an unmetered sandbox is the failure
# mode this profile exists to prevent.
resource "terraform_data" "starter_requires_budget" {
  count = local.profile == "starter" ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.monthly_budget_amount > 0
      error_message = "org.profile is starter but no monthly budget resolves: set org.monthly_budget_usd in config/landing-zone.yaml (or var.monthly_budget_amount) to a value above 0."
    }
  }
}
