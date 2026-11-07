# ── Single-source configuration: config/landing-zone.yaml ──────────────────
# Precedence: explicit variable (tfvars / TFC variable) > config file > built-in
# default. The file is optional; schema: config/landing-zone.example.yaml.
# local.cfg holds ONLY config-file values (it must not reference any variable
# except landing_zone_config_path: the variable validations read it).
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
    landing_zone_name        = try(tostring(local.lz.org.name), null)
    cost_center              = try(tostring(local.lz.org.cost_center), null)
    owner                    = try(tostring(local.lz.org.owner), null)
    aws_region               = try(tostring(local.lz.org.regions.aws), null)
    tfc_organization         = try(tostring(local.lz.org.tfc.organization), null)
    github_federation_owners = try([for o in local.lz.aws.github_federation_owners : tostring(o)], null)
    adopt = try(local.lz.aws.adopt, null) == null ? null : {
      organization_id = try(tostring(local.lz.aws.adopt.organization_id), null)
      ou_ids          = { for k, v in try(local.lz.aws.adopt.ou_ids, {}) : k => tostring(v) }
      account_ids     = { for k, v in try(local.lz.aws.adopt.account_ids, {}) : k => tostring(v) }
    }
    management_account_id   = try(tostring(local.lz.aws.management_account_id), null)
    log_archive_bucket_name = try(tostring(local.lz.aws.log_archive_bucket_name), null)
    allowed_regions         = try([for r in local.lz.aws.allowed_regions : tostring(r)], null)
    aws_enabled_regions     = try([for r in local.lz.aws.enabled_regions : tostring(r)], null)
    guard_alert_emails      = try([for e in local.lz.aws.guard_alert_emails : tostring(e)], null)
    profile                 = try(tostring(local.lz.org.profile), null)
    monthly_budget_usd      = try(tonumber(local.lz.org.monthly_budget_usd), null)
    notification_emails     = try([for e in local.lz.notifications.emails : tostring(e)], null)
    # Config recorder migration flags (docs/runbooks/aws-config-recorder-migration.md).
    enable_org_config_recorders = try(tobool(local.lz.aws.enable_org_config_recorders), null)
    enable_config_recorder_scp  = try(tobool(local.lz.aws.enable_config_recorder_scp), null)
    terraform_run_role_arn      = try(tostring(local.lz.aws.terraform_run_role_arn), null)
    break_glass_role_arn        = try(tostring(local.lz.aws.break_glass_role_arn), null)
    # tfc-admin puts the aws-* workspaces in <project_name_prefix>aws.
    tfc_project = try(tostring(local.lz.org.tfc.aws_project), "${try(tostring(local.lz.org.tfc.project_name_prefix), "landing-zone-")}aws")
    # With org.tfc.split_workload_projects, tfc-admin puts aws-workload-<env> in
    # <prefix>aws-workloads; the workload accounts' OIDC trust must name it.
    split_workload_projects = try(tobool(local.lz.org.tfc.split_workload_projects), false)
    tfc_workloads_project   = try(tostring(local.lz.org.tfc.aws_workloads_project), "${try(tostring(local.lz.org.tfc.project_name_prefix), "landing-zone-")}aws-workloads")
    # Accounts normalised to the attribute types of var.accounts.
    accounts          = { for k, a in try({ for k, a in local.lz.aws.accounts : k => a }, {}) : k => local.normalise_account[k] }
    workload_accounts = { for k, a in try({ for k, a in local.lz.aws.workload_accounts : k => a }, {}) : k => local.normalise_account[k] }
    # aws.workload_environments: env => account_key, grouped account_key => envs.
    workload_bindings = {
      for acct, envs in {
        for env, e in try({ for k, v in local.lz.aws.workload_environments : k => v }, {}) : tostring(e.account_key) => env... if try(e.account_key, null) != null
      } : acct => [for env in envs : "aws-workload-${env}"]
    }
  }

  # Every account entry from aws.accounts / aws.workload_accounts, normalised.
  raw_accounts = merge(
    try({ for k, a in local.lz.aws.accounts : k => a }, {}),
    try({ for k, a in local.lz.aws.workload_accounts : k => a }, {}),
  )
  normalise_account = {
    for k, a in local.raw_accounts : k => {
      email = tostring(try(a.email, ""))
      ou    = tostring(try(a.ou, ""))
      name  = try(tostring(a.name), null)
      alternate_contacts = try({
        for ck, c in a.alternate_contacts : ck => {
          contact_type  = tostring(c.contact_type)
          name          = tostring(c.name)
          title         = tostring(c.title)
          email_address = tostring(c.email_address)
          phone_number  = tostring(c.phone_number)
        }
      }, {})
      tags = try({ for tk, tv in a.tags : tk => tostring(tv) }, {})
    }
  }

  # Built-in fallback when neither var.accounts nor aws.accounts is set: the six
  # SRA foundational accounts with PLACEHOLDER emails, which the var.accounts
  # validation rejects (each account needs a real, unique, deliverable email).
  default_accounts = {
    for k, a in {
      log_archive      = { email = "aws+log-archive@example.com", ou = "Security" }
      security_tooling = { email = "aws+security-tooling@example.com", ou = "Security" }
      network          = { email = "aws+network@example.com", ou = "Infrastructure" }
      shared_services  = { email = "aws+shared-services@example.com", ou = "Infrastructure" }
      backup           = { email = "aws+backup@example.com", ou = "Infrastructure" }
      forensics        = { email = "aws+forensics@example.com", ou = "Security" }
    } : k => merge(a, { name = null, alternate_contacts = {}, tags = {} })
  }
  # Indexed tuple (not a conditional): the two objects have different keys.
  cfg_or_default_accounts = [local.cfg.accounts, local.default_accounts][length(local.cfg.accounts) > 0 ? 0 : 1]

  default_workspace_bindings = {
    security_tooling = ["aws-security"]
    log_archive      = ["aws-security"]
    forensics        = ["aws-security"]
    network          = ["aws-network"]
    shared_services  = ["aws-identity", "aws-shared-services"]
    backup           = ["aws-backup"]
  }

  # Required values fall back to an inert sentinel only so static tools (tflint)
  # can evaluate the root; the variable validations reject the unset case first.
  landing_zone_name        = coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "unset")
  cost_center              = var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform")
  owner                    = var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team")
  aws_region               = coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")
  tfc_organization         = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  github_federation_owners = coalesce(var.github_federation_owners, local.cfg.github_federation_owners, [])
  adopt_existing = (
    var.adopt_existing != null ? var.adopt_existing :
    local.cfg.adopt != null ? local.cfg.adopt :
    { organization_id = null, ou_ids = {}, account_ids = {} }
  )
  management_account_id   = coalesce(var.management_account_id, local.cfg.management_account_id, "000000000000")
  log_archive_bucket_name = coalesce(var.log_archive_bucket_name, local.cfg.log_archive_bucket_name, "unset")

  accounts          = var.accounts != null ? var.accounts : local.cfg_or_default_accounts
  workload_accounts = var.workload_accounts != null ? var.workload_accounts : local.cfg.workload_accounts
  allowed_regions   = var.allowed_regions != null ? var.allowed_regions : coalesce(local.cfg.allowed_regions, ["eu-west-2"])
  # Same precedence and fallback as the aws-security root: the guard alerts
  # forward from every region the security services run in.
  aws_enabled_regions = var.aws_enabled_regions != null ? var.aws_enabled_regions : coalesce(local.cfg.aws_enabled_regions, ["eu-west-2"])
  # variable > aws.guard_alert_emails > notifications.emails > none.
  notification_emails = coalesce(local.cfg.notification_emails, [])
  guard_alert_emails = var.guard_alert_emails != null ? var.guard_alert_emails : (
    length(coalesce(local.cfg.guard_alert_emails, [])) > 0 ? local.cfg.guard_alert_emails : local.notification_emails
  )
  # Budgets without their own recipients, and the single anomaly address, follow
  # notifications.emails (default: today's values).
  profile            = coalesce(var.profile, local.cfg.profile, "production")
  monthly_budget_usd = var.monthly_budget_usd != null ? var.monthly_budget_usd : local.cfg.monthly_budget_usd
  # The starter profile replaces the budget set with one budget sized from
  # org.monthly_budget_usd that alerts at 50/80/100% of actual spend (plus a
  # forecast at 100%). Requires the amount (terraform_data.starter_requires_budget).
  effective_budgets = local.profile == "starter" ? {
    org-monthly = {
      limit_amount      = tostring(coalesce(local.monthly_budget_usd, 0))
      threshold_percent = 100
      emails            = []
      alert_percents    = [50, 80, 100]
    }
  } : var.budgets
  budgets = {
    for k, b in local.effective_budgets : k => merge(b, { emails = length(b.emails) > 0 ? b.emails : local.notification_emails })
  }
  cost_anomaly_email = var.cost_anomaly_email != null ? var.cost_anomaly_email : (
    length(local.notification_emails) > 0 ? local.notification_emails[0] : "finops@example.com"
  )
  enable_org_config_recorders = var.enable_org_config_recorders != null ? var.enable_org_config_recorders : coalesce(local.cfg.enable_org_config_recorders, false)
  enable_config_recorder_scp  = var.enable_config_recorder_scp != null ? var.enable_config_recorder_scp : coalesce(local.cfg.enable_config_recorder_scp, false)
  terraform_run_role_arn      = coalesce(var.terraform_run_role_arn, local.cfg.terraform_run_role_arn, "arn:aws:iam::000000000000:role/unset")
  break_glass_role_arn        = coalesce(var.break_glass_role_arn, local.cfg.break_glass_role_arn, "arn:aws:iam::000000000000:role/unset")
  tfc_project                 = coalesce(var.tfc_project, local.cfg.tfc_project)
  # Foundational bindings + the workload bindings derived from the config file;
  # an explicit var.tfc_workspace_bindings replaces both.
  tfc_workspace_bindings = var.tfc_workspace_bindings != null ? var.tfc_workspace_bindings : {
    for acct in distinct(concat(keys(local.default_workspace_bindings), keys(local.cfg.workload_bindings))) : acct => {
      workspaces = distinct(concat(lookup(local.default_workspace_bindings, acct, []), lookup(local.cfg.workload_bindings, acct, [])))
      # Workload-only accounts trust the workloads project when it is split out.
      project = (
        local.cfg.split_workload_projects && length(lookup(local.default_workspace_bindings, acct, [])) == 0
        ? local.cfg.tfc_workloads_project : null
      )
    }
  }
}
