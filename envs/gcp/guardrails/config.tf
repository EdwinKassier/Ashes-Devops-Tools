# ── Single-source configuration: config/landing-zone.yaml ──────────────────
# Precedence: explicit variable (tfvars / TFC variable) > config file > built-in
# default. The file is optional; schema: config/landing-zone.example.yaml.
# local.cfg holds ONLY config-file values (it must not reference any variable
# except landing_zone_config_path: the variable validations read it). The block
# is identical in every GCP root; each root uses the keys it needs.
#
# gcp-guardrails authors the deny policies from this file alone (org.domain,
# gcp.environments[*].is_production, gcp.admin_containment,
# gcp.break_glass_group), the same keys gcp-organization reads to create and
# bind the containment tag, so the two roots agree without reading each other.
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
    project_prefix    = try(tostring(local.lz.org.prefix), null)
    domain            = try(tostring(local.lz.org.domain), null)
    break_glass_group = try(tostring(local.lz.gcp.break_glass_group), null)
    admin_containment = try(tobool(local.lz.gcp.admin_containment), null)
    # Only is_production matters here (normalised like the other GCP roots).
    environments = {
      for k, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : k => {
        is_production = tobool(try(e.is_production, false))
      }
    }
  }

  # Effective values. Required ones fall back to an inert sentinel only so
  # static tools (tflint) can evaluate the root; the variable validations reject
  # the unset case first.
  domain         = coalesce(var.domain, local.cfg.domain, "unset.invalid")
  project_prefix = coalesce(var.project_prefix, local.cfg.project_prefix, "unset")
  environments   = var.environments != null ? var.environments : local.cfg.environments

  # Admin containment follows the estate exactly as in gcp-organization: on
  # whenever a production environment exists, unless explicitly set
  # (variable > gcp.admin_containment > derived).
  production_environment_keys = sort([for k, e in local.environments : k if e.is_production])
  enable_admin_containment    = coalesce(var.enable_admin_containment, local.cfg.admin_containment, length(local.production_environment_keys) > 0)
  containment_exempt_principals = length(var.containment_exempt_principals) > 0 ? var.containment_exempt_principals : (
    local.cfg.break_glass_group != null ? ["principalSet://goog/group/${local.cfg.break_glass_group}"] : []
  )

  # Without a break-glass principal the stage is never asked for containment
  # (it would deny everyone); output.admin_containment_enabled fails the plan.
  containment_on = local.enable_admin_containment && length(local.containment_exempt_principals) > 0
}
