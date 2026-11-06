# ── Single-source configuration: config/landing-zone.yaml ──────────────────
# Same block as every envs/** root (copied from envs/gcp/projects/config.tf /
# envs/aws/workload/config.tf). Precedence: explicit variable (tfvars / TFC
# variable) > config file > built-in default. The file is optional; schema:
# config/landing-zone.example.yaml.
# local.cfg holds ONLY config-file values (it must not reference any variable
# except landing_zone_config_path: the variable validations read it). Add the
# keys this root needs to local.cfg and read the effective value as local.<name>.
locals {
  # "" disables the lookup; a relative path is resolved against this root.
  # Once cloned to envs/aws/<layer>/, the default resolves to the repo's
  # config/landing-zone.yaml (envs/aws/<layer> -> ../../../).
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
    aws_region          = try(tostring(local.lz.org.regions.aws), null)
    tfc_organization    = try(tostring(local.lz.org.tfc.organization), null)
    aws_enabled_regions = try([for r in local.lz.aws.enabled_regions : tostring(r)], null)

    # aws.contracts.organization: stage contract override (same shape as
    # var.organization_contract). Present => the remote-state read is skipped.
    organization_contract = try(local.lz.aws.contracts.organization, null) == null ? null : {
      account_ids = { for k, v in try(local.lz.aws.contracts.organization.account_ids, {}) : k => tostring(v) }
    }
  }

  # Effective values.
  aws_region          = coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")
  tfc_organization    = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  aws_enabled_regions = var.aws_enabled_regions != null ? var.aws_enabled_regions : coalesce(local.cfg.aws_enabled_regions, [local.aws_region])
}
