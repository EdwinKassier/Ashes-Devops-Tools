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
    log_archive_bucket_name = try(tostring(local.lz.aws.log_archive_bucket_name), null)
    aws_enabled_regions     = try([for r in local.lz.aws.enabled_regions : tostring(r)], null)
    # aws.network.*: Network Firewall egress posture.
    egress_domain_allowlist  = try([for d in local.lz.aws.network.egress_domain_allowlist : tostring(d)], null)
    stateful_default_actions = try([for a in local.lz.aws.network.stateful_default_actions : tostring(a)], null)
    egress_alert_only_waived = try(tobool(local.lz.aws.network.egress_alert_only_waived), null)
    # aws.network.vpn: opt-in Site-to-Site VPN on the TGW (no secret: AWS
    # generates the tunnel keys). JSON text so the explicit-variable fallback
    # is a plain conditional; the stage's variable type validates the shape.
    enable_vpn = try(tobool(local.lz.aws.network.vpn.enabled), null)
    vpn        = try(jsonencode(local.lz.aws.network.vpn), null)
    # aws.workload_environments production flags (unset = keys prod/production).
    workload_production = try([
      for k, e in local.lz.aws.workload_environments : k
      if coalesce(try(tobool(e.is_production), null), can(regex("^prod(uction)?$", k)))
    ], [])
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
  landing_zone_name       = coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "unset")
  cost_center             = var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform")
  owner                   = var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team")
  aws_region              = coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")
  tfc_organization        = try(coalesce(var.tfc_organization, local.cfg.tfc_organization), null)
  log_archive_bucket_name = coalesce(var.log_archive_bucket_name, local.cfg.log_archive_bucket_name, "unset")
  aws_enabled_regions     = var.aws_enabled_regions != null ? var.aws_enabled_regions : coalesce(local.cfg.aws_enabled_regions, ["eu-west-2"])

  # Profile-driven defaults (explicit variable > profile). starter drops the
  # Network Firewall endpoints (~$577/month idle at 2 AZs).
  profile                 = coalesce(var.profile, local.cfg.profile, "production")
  enable_network_firewall = coalesce(var.enable_network_firewall, local.profile == "production")

  # Production egress fails closed: on when the profile is production AND an
  # AWS workload environment is production (explicit variable wins).
  enforce_egress_allowlist                  = coalesce(var.enforce_egress_allowlist, local.profile == "production" && length(local.cfg.workload_production) > 0)
  network_firewall_egress_domain_allowlist  = var.network_firewall_egress_domain_allowlist != null ? var.network_firewall_egress_domain_allowlist : coalesce(local.cfg.egress_domain_allowlist, [])
  network_firewall_stateful_default_actions = var.network_firewall_stateful_default_actions != null ? var.network_firewall_stateful_default_actions : coalesce(local.cfg.stateful_default_actions, ["aws:alert_established"])
  egress_alert_only_waived                  = coalesce(var.egress_alert_only_waived, local.cfg.egress_alert_only_waived, false)
  # Opt-in hybrid connectivity (default off: no VPN).
  enable_vpn = coalesce(var.enable_vpn, local.cfg.enable_vpn, false)
  vpn        = jsondecode(var.vpn != null ? jsonencode(var.vpn) : coalesce(local.cfg.vpn, "{}"))
}
