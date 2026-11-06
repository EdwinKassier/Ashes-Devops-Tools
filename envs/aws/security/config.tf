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
    # aws.contracts.organization: stage contract override (same shape as
    # var.organization_contract). Present => the aws-organization read is skipped.
    organization_contract = try(local.lz.aws.contracts.organization, null) == null ? null : {
      organization_id       = try(tostring(local.lz.aws.contracts.organization.organization_id), null)
      organization_root_id  = try(tostring(local.lz.aws.contracts.organization.organization_root_id), null)
      management_account_id = try(tostring(local.lz.aws.contracts.organization.management_account_id), null)
      account_ids           = { for k, v in try(local.lz.aws.contracts.organization.account_ids, {}) : k => tostring(v) }
      account_role_arns     = { for k, v in try(local.lz.aws.contracts.organization.account_role_arns, {}) : k => tostring(v) }
    }
  }

  # Required values fall back to an inert sentinel only so static tools (tflint)
  # can evaluate the root; the variable validations reject the unset case first.
  landing_zone_name       = coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "unset")
  cost_center             = var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform")
  owner                   = var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team")
  aws_region              = coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")
  tfc_organization        = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  management_account_id   = coalesce(var.management_account_id, local.cfg.management_account_id, "000000000000")
  log_archive_bucket_name = coalesce(var.log_archive_bucket_name, local.cfg.log_archive_bucket_name, "unset")
  aws_enabled_regions     = var.aws_enabled_regions != null ? var.aws_enabled_regions : coalesce(local.cfg.aws_enabled_regions, ["eu-west-2"])

  # Profile-driven defaults (explicit variable > profile). starter keeps every
  # preventive and core detective control (CloudTrail, Config, GuardDuty,
  # Security Hub, Inspector) and drops the usage-scaling extras.
  profile                                 = coalesce(var.profile, local.cfg.profile, "production")
  starter                                 = local.profile == "starter"
  enable_security_lake                    = coalesce(var.enable_security_lake, !local.starter)
  enabled_security_services               = var.enabled_security_services != null ? var.enabled_security_services : (local.starter ? toset(["inspector"]) : toset(["macie", "inspector"]))
  config_record_all_supported             = coalesce(var.config_record_all_supported, !local.starter)
  guardduty_enable_ebs_malware_protection = coalesce(var.guardduty_enable_ebs_malware_protection, !local.starter)
}
