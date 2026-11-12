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
    landing_zone_name     = try(tostring(local.lz.org.name), null)
    cost_center           = try(tostring(local.lz.org.cost_center), null)
    owner                 = try(tostring(local.lz.org.owner), null)
    aws_region            = try(tostring(local.lz.org.regions.aws), null)
    tfc_organization      = try(tostring(local.lz.org.tfc.organization), null)
    management_account_id = try(tostring(local.lz.aws.management_account_id), null)
    # compliance.backup: central copy to the locked copy vault and the
    # cross-region copy. compliance.audit_log_retention_days does not apply:
    # backup retention is a separate decision.
    backup_copy_to_central_vault = try(tobool(local.lz.compliance.backup.copy_to_central_vault), null)
    backup_copy_retention_days   = try(tonumber(local.lz.compliance.backup.copy_retention_days), null)
    backup_dr_region             = try(tostring(local.lz.compliance.backup.dr_region), null)
    # aws.allowed_regions: the region SCP allow-list (aws-organization). The
    # dr_region validation uses the same fallback, ["eu-west-2"].
    allowed_regions = try([for r in local.lz.aws.allowed_regions : tostring(r)], null)
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

  # Required values fall back to an inert sentinel only so static tools (tflint)
  # can evaluate the root; the variable validations reject the unset case first.
  landing_zone_name     = coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "unset")
  cost_center           = var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform")
  owner                 = var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team")
  aws_region            = coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")
  tfc_organization      = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  management_account_id = coalesce(var.management_account_id, local.cfg.management_account_id, "000000000000")
  enable_central_copy   = coalesce(var.enable_central_copy, local.cfg.backup_copy_to_central_vault, false)
  copy_retention_days   = coalesce(var.copy_retention_days, local.cfg.backup_copy_retention_days, 365)
  dr_region             = var.dr_region != null ? var.dr_region : local.cfg.backup_dr_region
}
