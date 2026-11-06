# ── Single-source configuration: config/landing-zone.yaml ──────────────────
# Precedence: explicit variable (tfvars / TFC variable) > config file > built-in
# default. The file is optional; schema: config/landing-zone.example.yaml.
# local.cfg holds ONLY config-file values (it must not reference any variable
# except landing_zone_config_path: the variable validations read it).
locals {
  # "" disables the lookup; a relative path is resolved against this root.
  landing_zone_config_file = var.landing_zone_config_path == "" ? null : (
    var.landing_zone_config_path == null ? "${path.root}/../../config/landing-zone.yaml" : (
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
    tfc_organization = try(tostring(local.lz.org.tfc.organization), null)
    enable_supabase  = try(tobool(local.lz.saas.supabase), null)
    enable_vercel    = try(tobool(local.lz.saas.vercel), null)
  }

  tfc_organization = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  enable_supabase  = var.enable_supabase != null ? var.enable_supabase : coalesce(local.cfg.enable_supabase, true)
  enable_vercel    = var.enable_vercel != null ? var.enable_vercel : coalesce(local.cfg.enable_vercel, true)
}
