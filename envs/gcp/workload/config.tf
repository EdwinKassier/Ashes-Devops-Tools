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
    saas_bridge_rotation      = try(tonumber(local.lz.saas.bridge_rotation), null)
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
        region                  = tostring(try(e.region, local.lz.org.regions.gcp, "europe-west2"))
        cidr_block              = tostring(try(e.cidr_block, ""))
        budget_monthly_limit    = tonumber(try(e.budget_monthly_limit, 0))
        iam_group_role_bindings = try({ for g, roles in e.iam_group_role_bindings : g => toset([for r in roles : tostring(r)]) }, {})
        labels                  = try({ for lk, lv in e.labels : lk => tostring(lv) }, {})
        is_production           = tobool(try(e.is_production, false))
      }
    }

    # gcp.environments.<env>.services: app golden-path services per environment
    # (same shape as var.app_services; the app-services stage validates and
    # types them).
    app_services = {
      for env, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : env => { for k, v in e.services : k => v }
      if try(e.services, null) != null
    }
    # gcp.environments.<env>.service_teams: normalised to the attribute types of
    # var.service_teams.
    service_teams = {
      for env, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : env => {
        for team, t in e.service_teams : team => {
          project_admin_group_email    = tostring(t.project_admin_group_email)
          activate_apis                = [for a in try(t.activate_apis, []) : tostring(a)]
          project_admin_roles          = [for r in try(t.project_admin_roles, []) : tostring(r)]
          enable_shared_vpc_attachment = tobool(try(t.enable_shared_vpc_attachment, true))
          enable_gke_network_user      = tobool(try(t.enable_gke_network_user, false))
          shared_vpc_subnets = {
            for k, sn in try(t.shared_vpc_subnets, {}) : k => {
              region      = tostring(sn.region)
              subnet_name = tostring(sn.subnet_name)
            }
          }
          labels = { for lk, lv in try(t.labels, {}) : lk => tostring(lv) }
        }
      } if try(e.service_teams, null) != null
    }

    # gcp.contracts.<layer>: stage contract overrides (same shape as the
    # <layer>_contract variables). Present => that remote-state read is skipped.
    organization_contract = try(local.lz.gcp.contracts.organization, null) == null ? null : {
      org_id                   = tostring(local.lz.gcp.contracts.organization.org_id)
      billing_account          = tostring(local.lz.gcp.contracts.organization.billing_account)
      admin_project_number     = tostring(local.lz.gcp.contracts.organization.admin_project_number)
      folders                  = { for k, f in try({ for k, f in local.lz.gcp.contracts.organization.folders : k => f }, {}) : k => { id = tostring(f.id), name = tostring(try(f.name, f.id)), display_name = tostring(try(f.display_name, k)) } }
      tag_values               = { for k, v in try(local.lz.gcp.contracts.organization.tag_values, {}) : k => tostring(v) }
      scoped_access_policy_ids = { for k, v in try(local.lz.gcp.contracts.organization.scoped_access_policy_ids, {}) : k => tostring(v) }
    }
    projects_contract = try(local.lz.gcp.contracts.projects, null) == null ? null : {
      project_ids     = { for k, v in try(local.lz.gcp.contracts.projects.project_ids, {}) : k => tostring(v) }
      project_numbers = { for k, v in try(local.lz.gcp.contracts.projects.project_numbers, {}) : k => tostring(v) }
      environment_config = {
        for k, e in try({ for k, e in local.lz.gcp.contracts.projects.environment_config : k => e }, {}) : k => {
          folder_id               = tostring(e.folder_id)
          host_project_id         = tostring(e.host_project_id)
          host_project_number     = tostring(e.host_project_number)
          region                  = tostring(e.region)
          cidr_block              = tostring(e.cidr_block)
          labels                  = try({ for lk, lv in e.labels : lk => tostring(lv) }, {})
          is_production           = try(tobool(e.is_production), null)
          vpc_sc_access_policy_id = try(tostring(e.vpc_sc_access_policy_id), null)
        }
      }
    }
    # gcp.workload: app golden-path settings shared by every gcp-workload-<env>.
    app_bootstrap_image = try(tostring(local.lz.gcp.workload.bootstrap_image), null)
    # gcp.workload.public_ingress.<env>.<service> = {domains, dns_managed_zone, enable_cdn}.
    public_ingress = {
      for env, svcs in try({ for k, v in local.lz.gcp.workload.public_ingress : k => v }, {}) : env => {
        for svc, c in try({ for k, v in svcs : k => v }, {}) : svc => {
          domains          = [for d in try(c.domains, []) : tostring(d)]
          dns_managed_zone = try(tostring(c.dns_managed_zone), null)
          enable_cdn       = tobool(try(c.enable_cdn, false))
        }
      }
    }

    network_hub_contract = try(local.lz.gcp.contracts.network_hub, null) == null ? null : {
      vpc_self_link   = tostring(local.lz.gcp.contracts.network_hub.vpc_self_link)
      dns_domain      = tostring(local.lz.gcp.contracts.network_hub.dns_domain)
      ncc_hub_id      = try(tostring(local.lz.gcp.contracts.network_hub.ncc_hub_id), null)
      ncc_spoke_group = try(tostring(local.lz.gcp.contracts.network_hub.ncc_spoke_group), null)
    }

    # Hub connectivity: gcp.environments.<env>.network_connectivity, else
    # gcp.network.connectivity (peering | ncc).
    network_connectivity = try(tostring(local.lz.gcp.network.connectivity), null)
    environment_connectivity = {
      for env, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : env => tostring(e.network_connectivity)
      if try(e.network_connectivity, null) != null
    }
    # gcp.environments.<env>.additional_regions as JSON text (no type
    # unification across environments); the stage's variable type validates it.
    environment_additional_regions = {
      for env, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : env => jsonencode(e.additional_regions)
      if try(e.additional_regions, null) != null
    }
  }

  # Effective values. Required ones fall back to an inert sentinel only so
  # static tools (tflint) can evaluate the root; the variable validations reject
  # the unset case first.
  project_prefix   = coalesce(var.project_prefix, local.cfg.project_prefix, "unset")
  tfc_organization = coalesce(var.tfc_organization, local.cfg.tfc_organization, "unset")
  # Write-only version of the bridged secret (saas.bridge_rotation, the counter
  # the saas root publishes as bridge_version).
  saas_bridge_version = coalesce(var.saas_bridge_version, local.cfg.saas_bridge_rotation, 1)
  # This environment's region: gcp.environments[<env>].region, else
  # org.regions.gcp, else europe-west2 (the same default gcp-projects applies).
  region = coalesce(var.region, try(local.cfg.environments[var.environment].region, null), local.cfg.default_region, "europe-west2")
  # Opt-in extra spoke regions (default none: single-region spoke).
  additional_regions = jsondecode(var.additional_regions != null ? jsonencode(var.additional_regions) : lookup(local.cfg.environment_additional_regions, var.environment, "{}"))

  # Service teams / app services: explicit variable > gcp.environments.<env> in
  # the config file > none. Built with for-expressions (not a conditional) so
  # the differently-typed sources need no type unification.
  service_teams = merge(
    { for k, t in coalesce(var.service_teams, {}) : k => t },
    { for k, t in try(local.cfg.service_teams[var.environment], {}) : k => t if var.service_teams == null },
  )
  app_services_input = merge(
    { for k, s in coalesce(var.app_services, {}) : k => s },
    { for k, s in try(local.cfg.app_services[var.environment], {}) : k => s if var.app_services == null },
  )
}

# ── Presets: `presets` in config/landing-zone.yaml ─────────────────────────
# Named hardening/cost overlays from examples/presets/<name>.yaml (the YAML twin
# of <name>.tfvars, kept in step by tests/presets.tftest.hcl). A listed preset is
# applied only by the root its `root:` names; every other root ignores it. This
# root also applies gcp.workload.presets_by_environment[<environment>] (so a
# prod-only preset does not harden dev). Precedence: explicit variable > preset
# > config file > built-in default. Supported keys: local.preset_supported_keys.
locals {
  preset_root = "envs/gcp/workload"
  preset_names = distinct(concat(
    try([for n in local.lz.presets : tostring(n)], []),
    try([for n in local.lz.gcp.workload.presets_by_environment[var.environment] : tostring(n)], []),
  ))
  preset_documents = [for n in local.preset_names : yamldecode(file("${path.root}/../../../examples/presets/${n}.yaml"))]
  preset = merge([
    for d in local.preset_documents : { for k, v in try(d.values, {}) : k => v } if try(d.root, "") == local.preset_root
  ]...)
  preset_supported_keys = ["vpc_sc_enable_dry_run", "enable_cloud_armor", "enable_owasp_rules"]

  # Effective preset-backed values.
  vpc_sc_enable_dry_run = var.vpc_sc_enable_dry_run != null ? var.vpc_sc_enable_dry_run : tobool(lookup(local.preset, "vpc_sc_enable_dry_run", true))
  enable_cloud_armor    = var.enable_cloud_armor != null ? var.enable_cloud_armor : tobool(lookup(local.preset, "enable_cloud_armor", false))
  enable_owasp_rules    = var.enable_owasp_rules != null ? var.enable_owasp_rules : tobool(lookup(local.preset, "enable_owasp_rules", false))
}
