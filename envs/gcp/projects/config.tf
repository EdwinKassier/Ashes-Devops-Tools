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
    hub_vpc_cidr_block        = try(tostring(local.lz.gcp.network.hub_cidr_block), null)
    dns_hub_vpc_cidr_block    = try(tostring(local.lz.gcp.network.dns_hub_cidr_block), null)
    # Normalised to the attribute types of var.environments (region defaults to
    # org.regions.gcp, display_name to the key). A malformed entry is caught by
    # the var.environments validations, which also read local.cfg.
    environments = {
      for k, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : k => {
        display_name            = tostring(try(e.display_name, k))
        region                  = tostring(try(e.region, local.lz.org.regions.gcp, "europe-west1"))
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
  project_prefix    = coalesce(var.project_prefix, local.cfg.project_prefix, "unset")
  organization_name = coalesce(var.organization_name, local.cfg.organization_name, "My Organization")
  default_region    = coalesce(var.default_region, local.cfg.default_region, "europe-west1")
  tfc_organization  = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  environments      = var.environments != null ? var.environments : local.cfg.environments
}
