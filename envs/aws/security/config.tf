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
    landing_zone_name       = try(tostring(local.lz.org.name), null)
    profile                 = try(tostring(local.lz.org.profile), null)
    cost_center             = try(tostring(local.lz.org.cost_center), null)
    owner                   = try(tostring(local.lz.org.owner), null)
    aws_region              = try(tostring(local.lz.org.regions.aws), null)
    tfc_organization        = try(tostring(local.lz.org.tfc.organization), null)
    management_account_id   = try(tostring(local.lz.aws.management_account_id), null)
    log_archive_bucket_name = try(tostring(local.lz.aws.log_archive_bucket_name), null)
    aws_enabled_regions     = try([for r in local.lz.aws.enabled_regions : tostring(r)], null)
    notification_emails     = try([for e in local.lz.notifications.emails : tostring(e)], null)
    # Same key, same value in the aws-organization root.
    enable_cloudtrail_delegated_admin = try(tobool(local.lz.aws.enable_cloudtrail_delegated_admin), null)
    create_management_trail           = try(tobool(local.lz.aws.create_management_trail), null)
    # aws.contracts.organization: stage contract override (same type as
    # var.organization_contract, identical in every aws root). Present => the
    # aws-organization read is skipped.
    organization_contract = try(local.lz.aws.contracts.organization, null) == null ? null : {
      organization_id       = try(tostring(local.lz.aws.contracts.organization.organization_id), null)
      organization_root_id  = try(tostring(local.lz.aws.contracts.organization.organization_root_id), null)
      management_account_id = try(tostring(local.lz.aws.contracts.organization.management_account_id), null)
      ou_ids                = { for k, v in try(local.lz.aws.contracts.organization.ou_ids, {}) : k => tostring(v) }
      account_ids           = { for k, v in try(local.lz.aws.contracts.organization.account_ids, {}) : k => tostring(v) }
      account_role_arns     = { for k, v in try(local.lz.aws.contracts.organization.account_role_arns, {}) : k => tostring(v) }
    }
  }

  # The aws section as the stage's aws object (config-backed keys only; every
  # other key is unset here). notifications.emails feeds the subscriber map, so
  # the effective object below keeps aws_overrides > config file > default.
  lz_aws = {
    log_archive_bucket_name = local.cfg.log_archive_bucket_name
    aws_enabled_regions     = local.cfg.aws_enabled_regions
    # Org trail managed by the CloudTrail delegated admin (security tooling).
    enable_cloudtrail_delegated_admin = local.cfg.enable_cloudtrail_delegated_admin
    create_management_trail           = local.cfg.create_management_trail
    # One email subscriber per notifications.emails entry.
    notification_subscribers = length(coalesce(local.cfg.notification_emails, [])) > 0 ? {
      for i, e in local.cfg.notification_emails : "notify-${i}" => { protocol = "email", endpoint = e }
    } : null
  }
  # A set (non-null) override key wins; an unset one keeps the config value.
  aws = merge(local.lz_aws, { for k, v in var.aws_overrides : k => v if v != null })

  # Effective org-section values. Required ones fall back to an inert sentinel
  # only so static tools (tflint) can evaluate the root; the validations reject
  # the unset case first.
  landing_zone_name     = coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "unset")
  cost_center           = var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform")
  owner                 = var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team")
  aws_region            = coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")
  tfc_organization      = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  management_account_id = coalesce(var.management_account_id, local.cfg.management_account_id, "000000000000")
  aws_enabled_regions   = local.aws.aws_enabled_regions != null ? local.aws.aws_enabled_regions : ["eu-west-2"]

  # aws_overrides > notifications.emails > a placeholder SecOps email.
  notification_subscribers = local.aws.notification_subscribers != null ? tomap(local.aws.notification_subscribers) : tomap({
    secops = { protocol = "email", endpoint = "secops@example.com" }
  })

  # Profile-driven defaults (aws_overrides > profile). starter keeps every
  # preventive and core detective control (CloudTrail, Config, GuardDuty,
  # Security Hub, Inspector) and drops the usage-scaling extras.
  profile                                 = coalesce(var.profile, local.cfg.profile, "production")
  starter                                 = local.profile == "starter"
  enable_security_lake                    = coalesce(try(local.aws.enable_security_lake, null), !local.starter)
  enabled_security_services               = try(local.aws.enabled_security_services, null) != null ? toset(local.aws.enabled_security_services) : (local.starter ? toset(["inspector"]) : toset(["macie", "inspector"]))
  config_record_all_supported             = coalesce(try(local.aws.config_record_all_supported, null), !local.starter)
  guardduty_enable_ebs_malware_protection = coalesce(try(local.aws.guardduty_enable_ebs_malware_protection, null), !local.starter)
}
