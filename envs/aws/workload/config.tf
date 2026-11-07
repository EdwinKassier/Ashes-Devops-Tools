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
    landing_zone_name   = try(tostring(local.lz.org.name), null)
    cost_center         = try(tostring(local.lz.org.cost_center), null)
    owner               = try(tostring(local.lz.org.owner), null)
    aws_region          = try(tostring(local.lz.org.regions.aws), null)
    tfc_organization    = try(tostring(local.lz.org.tfc.organization), null)
    aws_enabled_regions = try([for r in local.lz.aws.enabled_regions : tostring(r)], null)
    # aws.workload_environments: env => {account_key, vpc_cidr}.
    workload_account_keys = { for env, e in try({ for k, v in local.lz.aws.workload_environments : k => v }, {}) : env => tostring(e.account_key) if try(e.account_key, null) != null }
    vpc_cidrs             = { for env, e in try({ for k, v in local.lz.aws.workload_environments : k => v }, {}) : env => tostring(e.vpc_cidr) if try(e.vpc_cidr, null) != null }
    # aws.workload_environments.<env>.services: same shape as var.services (the
    # app-services stage validates and types them).
    services = {
      for env, e in try({ for k, v in local.lz.aws.workload_environments : k => v }, {}) : env => { for k, v in e.services : k => v }
      if try(e.services, null) != null
    }
    # aws.contracts.<layer>: stage contract overrides (same shape as the
    # <layer>_contract variables). Present => that remote-state read is skipped.
    organization_contract = try(local.lz.aws.contracts.organization, null) == null ? null : {
      organization_id       = try(tostring(local.lz.aws.contracts.organization.organization_id), null)
      organization_root_id  = try(tostring(local.lz.aws.contracts.organization.organization_root_id), null)
      management_account_id = try(tostring(local.lz.aws.contracts.organization.management_account_id), null)
      ou_ids                = { for k, v in try(local.lz.aws.contracts.organization.ou_ids, {}) : k => tostring(v) }
      account_ids           = { for k, v in try(local.lz.aws.contracts.organization.account_ids, {}) : k => tostring(v) }
      account_role_arns     = { for k, v in try(local.lz.aws.contracts.organization.account_role_arns, {}) : k => tostring(v) }
    }
    network_contract = try(local.lz.aws.contracts.network, null) == null ? null : {
      tgw_id        = try(tostring(local.lz.aws.contracts.network.tgw_id), null)
      ipam_pool_ids = { for k, v in try(local.lz.aws.contracts.network.ipam_pool_ids, {}) : k => tostring(v) }
    }
    # aws.workload: app golden-path settings shared by every aws-workload-<env>.
    app_ingress_mode    = try(tostring(local.lz.aws.workload.app_ingress_mode), null)
    app_bootstrap_image = try(tostring(local.lz.aws.workload.bootstrap_image), null)
    security_contract = try(local.lz.aws.contracts.security.log_archive_bucket_name, null) == null ? null : {
      log_archive_bucket_name = tostring(local.lz.aws.contracts.security.log_archive_bucket_name)
    }
    # saas.bridge_rotation: the counter the saas root publishes as bridge_version.
    saas_bridge_rotation = try(tonumber(local.lz.saas.bridge_rotation), null)
  }

  # Required values fall back to an inert sentinel only so static tools (tflint)
  # can evaluate the root; the variable validations reject the unset case first.
  landing_zone_name    = coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "unset")
  cost_center          = var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform")
  owner                = var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team")
  aws_region           = coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")
  tfc_organization     = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  aws_enabled_regions  = var.aws_enabled_regions != null ? var.aws_enabled_regions : coalesce(local.cfg.aws_enabled_regions, ["eu-west-2"])
  workload_account_key = coalesce(var.workload_account_key, try(local.cfg.workload_account_keys[var.environment], null), "unset")
  vpc_cidr             = coalesce(var.vpc_cidr, try(local.cfg.vpc_cidrs[local.environment], null), "10.20.0.0/16")
  app_bootstrap_image  = coalesce(var.app_bootstrap_image, local.cfg.app_bootstrap_image, "public.ecr.aws/nginx/nginx-unprivileged:stable-alpine")
  saas_bridge_version  = coalesce(var.saas_bridge_version, local.cfg.saas_bridge_rotation, 1)

  # Services: explicit variable > aws.workload_environments.<env>.services >
  # none. For-expressions (not a conditional) so the differently-typed sources
  # need no type unification.
  services = merge(
    { for k, v in coalesce(var.services, {}) : k => v },
    { for k, v in try(local.cfg.services[local.environment], {}) : k => v if var.services == null },
  )
}
