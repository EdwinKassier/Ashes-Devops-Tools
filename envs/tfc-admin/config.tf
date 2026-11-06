# ── Single-source configuration: config/landing-zone.yaml ──────────────────
# Precedence: explicit variable (tfvars / TFC variable) > config file > built-in
# default. The file is optional; schema: config/landing-zone.example.yaml.
# local.cfg holds ONLY config-file values (it must not reference any variable
# except landing_zone_config_path: the variable validations read it).
#
# tfc-admin derives the whole workspace layer from the same file the cloud roots
# read: which clouds exist (gcp/aws/saas .enabled), the per-env workload
# workspaces (gcp.environments keys, aws.workload_environments), each
# aws-workload-<env>'s workload_account_key, the saas-<name> workspaces, the
# TFC project names and the VCS connection.
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
    tfc_organization    = try(tostring(local.lz.org.tfc.organization), null)
    project_name_prefix = try(tostring(local.lz.org.tfc.project_name_prefix), null)
    # Project keys: one per cloud, plus gcp-workloads / aws-workloads when
    # split_workload_projects is on (config keys org.tfc.<cloud>_project and
    # org.tfc.<cloud>_workloads_project).
    project_names = {
      for c in local.project_name_keys : c => try(tostring(local.lz.org.tfc["${replace(c, "-", "_")}_project"]), null)
    }
    split_workload_projects = try(tobool(local.lz.org.tfc.split_workload_projects), null)
    vcs_repo = try({
      identifier                 = tostring(local.lz.org.tfc.vcs_repo.identifier)
      branch                     = tostring(try(local.lz.org.tfc.vcs_repo.branch, "main"))
      oauth_token_id             = try(tostring(local.lz.org.tfc.vcs_repo.oauth_token_id), null)
      github_app_installation_id = try(tostring(local.lz.org.tfc.vcs_repo.github_app_installation_id), null)
    }, null)
    enable_gcp      = try(tobool(local.lz.gcp.enabled), null)
    enable_aws      = try(tobool(local.lz.aws.enabled), null)
    enable_saas     = try(tobool(local.lz.saas.enabled), null)
    saas_workspaces = try([for n in local.lz.saas.workspaces : tostring(n)], null)
    # gcp-workload-<env> per gcp.environments key; aws-workload-<env> per
    # aws.workload_environments key (with its account key).
    gcp_environment_keys = try(keys(local.lz.gcp.environments), [])
    # env => is_production (null when the key is absent).
    gcp_production = {
      for k, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : k => try(tobool(e.is_production), null)
    }
    aws_environments = tomap({
      for k, e in try({ for k, e in local.lz.aws.workload_environments : k => e }, {}) :
      k => { aws_account_key = try(tostring(e.account_key), null), is_production = try(tobool(e.is_production), null) }
    })
  }

  project_name_keys = ["gcp", "aws", "saas", "platform", "gcp-workloads", "aws-workloads"]

  # Effective values. Required ones fall back to an inert sentinel only so
  # static tools (tflint) can evaluate the root; the variable validations reject
  # the unset case first.
  tfc_organization    = coalesce(var.tfc_organization, local.cfg.tfc_organization, "unset")
  enable_gcp          = var.enable_gcp != null ? var.enable_gcp : coalesce(local.cfg.enable_gcp, false)
  enable_aws          = var.enable_aws != null ? var.enable_aws : coalesce(local.cfg.enable_aws, false)
  enable_saas         = var.enable_saas != null ? var.enable_saas : coalesce(local.cfg.enable_saas, false)
  saas_workspaces     = var.saas_workspaces != null ? var.saas_workspaces : coalesce(local.cfg.saas_workspaces, [])
  project_name_prefix = var.project_name_prefix != null ? var.project_name_prefix : coalesce(local.cfg.project_name_prefix, "landing-zone-")
  vcs_repo            = var.vcs_repo != null ? var.vcs_repo : local.cfg.vcs_repo

  # TFC project per cloud: an explicit org.tfc.<cloud>_project wins over
  # <project_name_prefix><cloud>. aws-organization derives its OIDC-trust
  # tfc_project from the same keys, so the two always agree.
  project_names = {
    for c in local.project_name_keys : c => coalesce(local.cfg.project_names[c], "${local.project_name_prefix}${c}")
  }
  split_workload_projects = var.split_workload_projects != null ? var.split_workload_projects : coalesce(local.cfg.split_workload_projects, false)

  # An explicit var.environments drives BOTH clouds' workload workspaces (the
  # pre-config behaviour); otherwise each cloud uses its own config section.
  gcp_environment_keys = var.environments != null ? keys(var.environments) : local.cfg.gcp_environment_keys
  aws_environments = var.environments != null ? tomap({
    for k, e in var.environments : k => { aws_account_key = e.aws_account_key, is_production = e.is_production }
  }) : local.cfg.aws_environments

  # Production environments: an explicit is_production wins; unset falls back
  # to the key name (prod / production), so a prod env is never missed.
  gcp_production_flags = var.environments != null ? { for k, e in var.environments : k => e.is_production } : local.cfg.gcp_production
  production_workloads = toset(concat(
    [for k in local.gcp_environment_keys : "gcp-workload-${k}" if coalesce(lookup(local.gcp_production_flags, k, null), can(regex("^prod(uction)?$", k)))],
    [for k, e in local.aws_environments : "aws-workload-${k}" if coalesce(e.is_production, can(regex("^prod(uction)?$", k)))],
  ))
}
