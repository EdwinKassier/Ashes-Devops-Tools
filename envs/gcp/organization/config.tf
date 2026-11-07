# ── Single-source configuration: config/landing-zone.yaml ──────────────────
# Precedence: explicit variable (tfvars / TFC variable) > config file > built-in
# default. The file is optional; schema: config/landing-zone.example.yaml.
# local.cfg holds ONLY config-file values (it must not reference any variable
# except landing_zone_config_path: the variable validations read it). The block
# is identical in every GCP root; each root uses the keys it needs.
locals {
  # "" disables the lookup; a relative path is resolved against this root.
  landing_zone_config_file = var.landing_zone_config_path == "" ? null : (
    var.landing_zone_config_path == null ? "${path.root}/../../../config/landing-zone.yaml" : (
      startswith(var.landing_zone_config_path, "/") ? var.landing_zone_config_path : "${path.root}/${var.landing_zone_config_path}"
    )
  )
  # A list (not a conditional) so the decoded document needs no type
  # unification with {}; malformed YAML still fails loudly.
  lz_documents = [
    for f in compact([local.landing_zone_config_file != null && fileexists(coalesce(local.landing_zone_config_file, "/nonexistent")) ? local.landing_zone_config_file : ""]) :
    yamldecode(file(f))
  ]
  lz = try(local.lz_documents[0], {})

  cfg = {
    project_prefix            = try(tostring(local.lz.org.prefix), null)
    organization_name         = try(tostring(local.lz.org.display_name), null)
    domain                    = try(tostring(local.lz.org.domain), null)
    default_region            = try(tostring(local.lz.org.regions.gcp), null)
    tfc_organization          = try(tostring(local.lz.org.tfc.organization), null)
    billing_account           = try(tostring(local.lz.gcp.billing_account), null)
    admin_email               = try(tostring(local.lz.gcp.admin_email), null)
    organization_admin_groups = try([for g in local.lz.gcp.organization_admin_groups : tostring(g)], null)
    billing_admin_groups      = try([for g in local.lz.gcp.billing_admin_groups : tostring(g)], null)
    allowed_regions           = try([for r in local.lz.gcp.allowed_regions : tostring(r)], null)
    break_glass_group         = try(tostring(local.lz.gcp.break_glass_group), null)
    profile                   = try(tostring(local.lz.org.profile), null)
    monthly_budget_usd        = try(tonumber(local.lz.org.monthly_budget_usd), null)
    alert_emails              = try([for e in local.lz.gcp.alert_emails : tostring(e)], null)
    notification_emails       = try([for e in local.lz.notifications.emails : tostring(e)], null)
    admin_containment         = try(tobool(local.lz.gcp.admin_containment), null)
    principal_access_boundary = try(tobool(local.lz.gcp.principal_access_boundary), null)
    enable_audit_bucket_lock  = try(tobool(local.lz.gcp.enable_audit_bucket_lock), null)
    hub_vpc_cidr_block        = try(tostring(local.lz.gcp.network.hub_cidr_block), null)
    dns_hub_vpc_cidr_block    = try(tostring(local.lz.gcp.network.dns_hub_cidr_block), null)
    # gcp.contracts.bootstrap: stage contract override (same shape as the
    # bootstrap_contract variable). Present => the remote-state read is skipped.
    bootstrap_contract = try(local.lz.gcp.contracts.bootstrap.admin_project_number, null) == null ? null : {
      admin_project_id      = tostring(local.lz.gcp.contracts.bootstrap.admin_project_id)
      admin_project_number  = tostring(local.lz.gcp.contracts.bootstrap.admin_project_number)
      terraform_admin_email = tostring(local.lz.gcp.contracts.bootstrap.terraform_admin_email)
      workload_service_accounts = {
        for k, sa in try({ for k, sa in local.lz.gcp.contracts.bootstrap.workload_service_accounts : k => sa }, {}) : k => { plan = tostring(sa.plan), apply = tostring(sa.apply) }
      }
      stage_service_accounts = {
        for k, sa in try({ for k, sa in local.lz.gcp.contracts.bootstrap.stage_service_accounts : k => sa }, {}) : k => { plan = tostring(sa.plan), apply = tostring(sa.apply) }
      }
      delegated_workload_folder_roles = [for r in try(local.lz.gcp.contracts.bootstrap.delegated_workload_folder_roles, []) : tostring(r)]
      delegated_network_folder_roles  = [for r in try(local.lz.gcp.contracts.bootstrap.delegated_network_folder_roles, []) : tostring(r)]
      guardrail_owner_mode            = tostring(try(local.lz.gcp.contracts.bootstrap.guardrail_owner_mode, "separate"))
    }
    # Normalised to the attribute types of var.environments (region defaults to
    # org.regions.gcp, display_name to the key). A malformed entry is caught by
    # the var.environments validations, which also read local.cfg.
    environments = {
      for k, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : k => {
        display_name            = tostring(try(e.display_name, k))
        region                  = tostring(try(e.region, local.lz.org.regions.gcp, "europe-west2"))
        cidr_block              = tostring(try(e.cidr_block, ""))
        budget_monthly_limit    = tonumber(try(e.budget_monthly_limit, 0))
        iam_group_role_bindings = try({ for g, roles in e.iam_group_role_bindings : g => toset([for r in roles : tostring(r)]) }, {})
        labels                  = try({ for lk, lv in e.labels : lk => tostring(lv) }, {})
        is_production           = tobool(try(e.is_production, false))
      }
    }
  }

  # Effective values. Required ones fall back to an inert sentinel only so
  # static tools (tflint) can evaluate the root; the variable validations reject
  # the unset case first.
  domain                    = coalesce(var.domain, local.cfg.domain, "unset.invalid")
  project_prefix            = coalesce(var.project_prefix, local.cfg.project_prefix, "unset")
  organization_name         = coalesce(var.organization_name, local.cfg.organization_name, "My Organization")
  billing_account           = try(coalesce(var.billing_account, local.cfg.billing_account), null)
  tfc_organization          = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  environments              = var.environments != null ? var.environments : local.cfg.environments
  default_region            = coalesce(var.default_region, local.cfg.default_region, "europe-west2")
  allowed_regions           = var.allowed_regions != null ? var.allowed_regions : coalesce(local.cfg.allowed_regions, ["europe-west1", "europe-west2", "us-central1"])
  admin_email               = coalesce(var.admin_email, local.cfg.admin_email, "unset@unset.invalid")
  organization_admin_groups = var.organization_admin_groups != null ? var.organization_admin_groups : coalesce(local.cfg.organization_admin_groups, [])
  billing_admin_groups      = var.billing_admin_groups != null ? var.billing_admin_groups : coalesce(local.cfg.billing_admin_groups, [])

  # Admin containment follows the estate: on whenever a production environment
  # exists, unless explicitly set (variable > gcp.admin_containment > derived).
  production_environment_keys = sort([for k, e in coalesce(local.environments, {}) : k if e.is_production])
  enable_audit_bucket_lock    = coalesce(var.enable_audit_bucket_lock, local.cfg.enable_audit_bucket_lock, false)
  # gcp.principal_access_boundary is shared with gcp-bootstrap and gcp-guardrails,
  # so the boundary and its containment deny rules cannot drift apart.
  enable_principal_access_boundary = coalesce(var.enable_principal_access_boundary, local.cfg.principal_access_boundary, false)
  enable_admin_containment         = coalesce(var.enable_admin_containment, local.cfg.admin_containment, length(local.production_environment_keys) > 0)
  containment_exempt_principals = length(var.containment_exempt_principals) > 0 ? var.containment_exempt_principals : (
    local.cfg.break_glass_group != null ? ["principalSet://goog/group/${local.cfg.break_glass_group}"] : []
  )
  # variable > gcp.alert_emails > notifications.emails > none.
  alert_notification_emails = length(var.alert_notification_emails) > 0 ? var.alert_notification_emails : (
    length(coalesce(local.cfg.alert_emails, [])) > 0 ? local.cfg.alert_emails : coalesce(local.cfg.notification_emails, [])
  )
  # Cost profile (variable > org.profile > production). The starter profile
  # requires a budget (variable > org.monthly_budget_usd) and alerts at 50/80/100%.
  profile = coalesce(var.profile, local.cfg.profile, "production")
  monthly_budget_amount = coalesce(
    var.monthly_budget_amount, local.cfg.monthly_budget_usd, local.profile == "starter" ? 0 : 1000
  )
  budget_threshold_rules = local.profile == "starter" ? [
    { percent = 0.5, spend_basis = "CURRENT_SPEND" },
    { percent = 0.8, spend_basis = "CURRENT_SPEND" },
    { percent = 1.0, spend_basis = "CURRENT_SPEND" },
  ] : null
  # Budgets notify the control-plane email channels only when the estate opted
  # in through the notifications section (an existing estate's budget is untouched).
  notify_budget_channels = length(coalesce(local.cfg.notification_emails, [])) > 0
}
