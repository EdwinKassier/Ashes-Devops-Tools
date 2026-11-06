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
    landing_zone_name = try(tostring(local.lz.org.name), null)
    cost_center       = try(tostring(local.lz.org.cost_center), null)
    owner             = try(tostring(local.lz.org.owner), null)
    aws_region        = try(tostring(local.lz.org.regions.aws), null)
    tfc_organization  = try(tostring(local.lz.org.tfc.organization), null)
    # aws.contracts.organization: stage contract override (same shape as
    # var.organization_contract). Present => the aws-organization read is skipped.
    organization_contract = try(local.lz.aws.contracts.organization, null) == null ? null : {
      account_ids = { for k, v in try(local.lz.aws.contracts.organization.account_ids, {}) : k => tostring(v) }
    }
  }

  # Required values fall back to an inert sentinel only so static tools (tflint)
  # can evaluate the root; the variable validations reject the unset case first.
  landing_zone_name = coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "unset")
  cost_center       = var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform")
  owner             = var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team")
  aws_region        = coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")
  tfc_organization  = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
}
