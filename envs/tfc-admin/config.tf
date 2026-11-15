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

  # ── Per-estate trigger patterns ─────────────────────────────────────────
  # Every workspace triggers on its own estate's config only, so editing one
  # estate's YAML never queues the other's runs. Both config paths are
  # converted to repo-relative paths (this root sits at envs/tfc-admin, so
  # "../../" is the repo root; dirname() cleans "./../../x" to "../.."):
  #   - production (the landing-zone file sits in config/): the landing-zone
  #     file and the workspace_variables_file, exactly (never config/sandbox/**);
  #   - any other estate (config/sandbox/landing-zone.yaml): its whole
  #     directory, plus the workspace_variables_file if it lies outside it.
  # A disabled lookup ("") and an absolute landing-zone path keep the
  # production layout; an absolute workspace_variables_file has no known
  # relation to the repo and adds no pattern. A relative
  # path that leaves the repo is rejected by the variable validations.
  # One local per path (a shared one would make the two variable validations
  # depend on each other).
  estate_landing_zone_path = [for p in [var.landing_zone_config_path == "" || var.landing_zone_config_path == null ? "../../config/landing-zone.yaml" : var.landing_zone_config_path] :
    (p == null ? null : (startswith(p, "/") ? null : (
      dirname("./${p}") == "../.." ? basename(p) : (
        startswith(dirname("./${p}"), "../../") ? "${trimprefix(dirname("./${p}"), "../../")}/${basename(p)}" : (
          dirname("./${p}") == "." ? "envs/tfc-admin/${basename(p)}" : "envs/tfc-admin/${dirname("./${p}")}/${basename(p)}"
        )
      )
    )))
  ][0]
  estate_workspace_vars_path = [for p in [var.workspace_variables_file] :
    (p == null ? null : (startswith(p, "/") ? null : (
      dirname("./${p}") == "../.." ? basename(p) : (
        startswith(dirname("./${p}"), "../../") ? "${trimprefix(dirname("./${p}"), "../../")}/${basename(p)}" : (
          dirname("./${p}") == "." ? "envs/tfc-admin/${basename(p)}" : "envs/tfc-admin/${dirname("./${p}")}/${basename(p)}"
        )
      )
    )))
  ][0]
  estate_config_dir = local.estate_landing_zone_path == null ? "config" : dirname(local.estate_landing_zone_path)
  estate_config_trigger_patterns = tolist(local.estate_config_dir == "config" ? concat(
    [coalesce(local.estate_landing_zone_path, "config/landing-zone.yaml")],
    local.estate_workspace_vars_path == null ? [] : [local.estate_workspace_vars_path],
    ) : concat(
    ["${local.estate_config_dir}/**"],
    local.estate_workspace_vars_path == null || startswith(coalesce(local.estate_workspace_vars_path, "/"), "${local.estate_config_dir}/") ? [] : [local.estate_workspace_vars_path],
  ))

  cfg = {
    tfc_organization   = try(tostring(local.lz.org.tfc.organization), null)
    hcp_email_user_ids = try([for u in local.lz.notifications.hcp_email_user_ids : tostring(u)], [])
    # The same key gcp-bootstrap reads as project_prefix: the <prefix> of its
    # <prefix>-wl-<env>-{plan,apply} workload service accounts.
    gcp_project_prefix  = try(tostring(local.lz.org.prefix), null)
    project_name_prefix = try(tostring(local.lz.org.tfc.project_name_prefix), null)
    # Project keys: one per cloud, plus gcp-workloads / aws-workloads when
    # split_workload_projects is on (config keys org.tfc.<cloud>_project and
    # org.tfc.<cloud>_workloads_project).
    project_names = {
      for c in local.project_name_keys : c => try(tostring(local.lz.org.tfc["${replace(c, "-", "_")}_project"]), null)
    }
    split_workload_projects = try(tobool(local.lz.org.tfc.split_workload_projects), null)
    tfc_plan                = try(tostring(local.lz.org.tfc.plan), null)
    # org.tfc.policy_sets_waiver: { reason, expires } (ADO-20). Normalised to
    # strings; a missing or malformed field becomes null and fails the
    # policy_sets_guard instead of being dropped.
    policy_sets_waiver = try(local.lz.org.tfc.policy_sets_waiver, null) == null ? null : {
      reason  = try(tostring(local.lz.org.tfc.policy_sets_waiver.reason), null)
      expires = try(tostring(local.lz.org.tfc.policy_sets_waiver.expires), null)
    }
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
    # aws.layers: the optional AWS layer workspaces (null = key absent).
    aws_layers = try([for l in local.lz.aws.layers : tostring(l)], null)
    # aws.contracts.network: aws-workload-<env> takes the hub contract from the
    # config file and reads no aws-network state.
    aws_network_contract = try(local.lz.aws.contracts.network, null) != null
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
    # Environments whose is_production is missing or not a boolean (the
    # environments validation names them).
    missing_is_production = sort(concat(
      [for k, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : "gcp.environments.${k}" if try(tobool(e.is_production), null) == null],
      [for k, e in try({ for k, e in local.lz.aws.workload_environments : k => e }, {}) : "aws.workload_environments.${k}" if try(tobool(e.is_production), null) == null],
    ))
    # CMP-1: regulated environments that are not is_production: true. A
    # regulated environment must get every production control.
    # Environment keys marked regulated in either cloud (re-audit 5 CMP-3:
    # checked against var.environments too, which a TFC variable can set).
    regulated_keys = sort(distinct(concat(
      [for k, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : k if try(tostring(e.compliance_class), "standard") == "regulated"],
      [for k, e in try({ for k, e in local.lz.aws.workload_environments : k => e }, {}) : k if try(tostring(e.compliance_class), "standard") == "regulated"],
    )))
    regulated_not_production = sort(concat(
      [for k, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : "gcp.environments.${k}" if try(tostring(e.compliance_class), "standard") == "regulated" && try(tobool(e.is_production), null) != true],
      [for k, e in try({ for k, e in local.lz.aws.workload_environments : k => e }, {}) : "aws.workload_environments.${k}" if try(tostring(e.compliance_class), "standard") == "regulated" && try(tobool(e.is_production), null) != true],
    ))
  }

  project_name_keys = ["gcp", "aws", "saas", "platform", "gcp-workloads", "aws-workloads", "guardrails"]

  # Effective values. Required ones fall back to an inert sentinel only so
  # static tools (tflint) can evaluate the root; the variable validations reject
  # the unset case first.
  tfc_organization   = coalesce(var.tfc_organization, local.cfg.tfc_organization, "unset")
  gcp_project_prefix = var.gcp_project_prefix != null ? var.gcp_project_prefix : local.cfg.gcp_project_prefix
  enable_gcp         = var.enable_gcp != null ? var.enable_gcp : coalesce(local.cfg.enable_gcp, false)
  enable_aws         = var.enable_aws != null ? var.enable_aws : coalesce(local.cfg.enable_aws, false)
  enable_saas        = var.enable_saas != null ? var.enable_saas : coalesce(local.cfg.enable_saas, false)
  saas_workspaces    = var.saas_workspaces != null ? var.saas_workspaces : coalesce(local.cfg.saas_workspaces, [])
  # Optional AWS layers (aws-<layer> workspaces); absent = all four, so an
  # existing estate keeps every workspace.
  aws_layers = var.aws_layers != null ? var.aws_layers : (
    local.cfg.aws_layers != null ? local.cfg.aws_layers : ["network", "identity", "shared-services", "backup"]
  )
  project_name_prefix = var.project_name_prefix != null ? var.project_name_prefix : coalesce(local.cfg.project_name_prefix, "landing-zone-")
  vcs_repo            = var.vcs_repo != null ? var.vcs_repo : local.cfg.vcs_repo
  tfc_plan            = var.tfc_plan != null ? var.tfc_plan : local.cfg.tfc_plan

  # notifications.hcp_email_user_ids: one email notification per workspace on
  # failed runs and on every health-assessment event. HCP email notifications
  # take user IDs (plain addresses work only on Terraform Enterprise). An
  # explicitly configured notification of the same name wins.
  config_email_notification = length(local.cfg.hcp_email_user_ids) == 0 ? {} : {
    notify-email = {
      destination_type = "email"
      url              = null
      token            = null
      email_user_ids   = local.cfg.hcp_email_user_ids
      triggers         = ["run:errored", "run:needs_attention", "assessment:drifted", "assessment:check_failure", "assessment:failed"]
      enabled          = true
    }
  }
  control_plane_notifications = merge(local.config_email_notification, var.control_plane_notifications)
  workload_notifications      = merge(local.config_email_notification, var.workload_notifications)
  # VCS-sourced policy sets on by default only where the plan enforces them
  # (free and essentials are left to an explicit enable_policy_sets = true).
  enable_policy_sets = var.enable_policy_sets != null ? var.enable_policy_sets : (
    local.vcs_repo != null && contains(["standard", "premium"], coalesce(local.tfc_plan, "unknown"))
  )

  # Policy-sets waiver (ADO-20): explicit variable > org.tfc.policy_sets_waiver.
  # It needs a reason and a real YYYY-MM-DD expiry, and waives through that UTC
  # day (the rule of the gcp-workload production waivers). yamldecode reads an
  # unquoted YAML date as YYYY-MM-DDT00:00:00Z: accept it and use the first 10
  # characters.
  policy_sets_waiver           = var.policy_sets_waiver != null ? var.policy_sets_waiver : local.cfg.policy_sets_waiver
  policy_sets_waiver_reason_ok = try(length(trimspace(local.policy_sets_waiver.reason)) > 0, false)
  policy_sets_waiver_expires   = try(substr(local.policy_sets_waiver.expires, 0, 10), null)
  policy_sets_waiver_expiry_ok = try(can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}(T00:00:00Z)?$", local.policy_sets_waiver.expires)) && can(formatdate("YYYY", "${local.policy_sets_waiver_expires}T00:00:00Z")), false)
  policy_sets_waiver_valid     = local.policy_sets_waiver == null || (local.policy_sets_waiver_reason_ok && local.policy_sets_waiver_expiry_ok)
  policy_sets_waiver_until     = local.policy_sets_waiver != null && local.policy_sets_waiver_valid ? "${local.policy_sets_waiver_expires}T23:59:59Z" : null
  policy_sets_waived           = local.policy_sets_waiver_until != null && timecmp(plantimestamp(), coalesce(local.policy_sets_waiver_until, "1970-01-01T00:00:00Z")) <= 0

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

  # Production environments: is_production true, nothing else (the variable
  # validation guarantees every environment states it).
  gcp_production_flags = var.environments != null ? { for k, e in var.environments : k => e.is_production } : local.cfg.gcp_production
  production_workloads = toset(concat(
    [for k in local.gcp_environment_keys : "${local.catalog_family.gcp}-${k}" if try(local.gcp_production_flags[k], null) == true],
    [for k, e in local.aws_environments : "${local.catalog_family.aws}-${k}" if e.is_production == true],
  ))
}

# ── Address plan (docs/architecture/cidr-plan.md) ──────────────────────────
# The cidrnetmask validations in each root only check that a CIDR is well
# formed. Overlap between the GCP and AWS ranges only shows up as broken routes
# once the clouds are joined (VPN / Interconnect), so tfc-admin, which reads the
# whole config file, fails its plan on any overlap. Explicit TFC variables on a
# network workspace are not visible here: keep them in the config file.
locals {
  cidr_gcp_ranges = local.enable_gcp ? {
    for k, c in merge(
      {
        "gcp.network.hub_cidr_block"     = try(tostring(local.lz.gcp.network.hub_cidr_block), null)
        "gcp.network.dns_hub_cidr_block" = try(tostring(local.lz.gcp.network.dns_hub_cidr_block), null)
      },
      { for env, e in try({ for k, e in local.lz.gcp.environments : k => e }, {}) : "gcp.environments.${env}.cidr_block" => try(tostring(e.cidr_block), null) },
    ) : k => c if c != null && can(cidrnetmask(c))
  } : {}

  # AWS VPCs with a fixed range: the hub VPCs (aws-network defaults when the
  # config sets none) and the workload VPCs. A workload without vpc_cidr uses
  # the aws-workload built-in 10.72.0.0/16, so two such workloads overlap and
  # fail here.
  cidr_aws_top = local.enable_aws ? try(tostring(local.lz.aws.network.top_cidr), "10.64.0.0/10") : null
  cidr_aws_ranges = local.enable_aws ? {
    for k, c in merge(
      {
        "aws.network.inspection_cidr" = try(tostring(local.lz.aws.network.inspection_cidr), "10.64.0.0/16")
        "aws.network.egress_cidr"     = try(tostring(local.lz.aws.network.egress_cidr), "10.65.0.0/16")
      },
      { for env, e in try({ for k, e in local.lz.aws.workload_environments : k => e }, {}) : "aws.workload_environments.${env}.vpc_cidr" => try(tostring(e.vpc_cidr), "10.72.0.0/16") },
    ) : k => c if c != null && can(cidrnetmask(c))
  } : {}

  # With the AWS VPN on, aws-network routes each on-premises prefix from the
  # egress VPC and the shared TGW table to the VPN, so none may overlap an AWS
  # (or GCP) range. They may overlap each other, and they are not held to
  # top_cidr or the pool. aws-network fails its own plan on an AWS overlap too.
  cidr_onprem_ranges = local.enable_aws && try(tobool(local.lz.aws.network.vpn.enabled), false) ? {
    for i, c in try(local.lz.aws.network.vpn.onprem_cidrs, []) : "aws.network.vpn.onprem_cidrs[${i}]" => tostring(c)
    if can(cidrnetmask(tostring(c)))
  } : {}

  # Two ranges overlap when their network addresses agree on the shorter prefix
  # (cidrhost masks the host bits of the address it is given).
  cidr_all = merge(
    local.cidr_gcp_ranges,
    local.cidr_aws_ranges,
    local.cidr_onprem_ranges,
    local.cidr_aws_top == null || !can(cidrnetmask(coalesce(local.cidr_aws_top, "x"))) ? {} : { "aws.network.top_cidr" = local.cidr_aws_top },
  )
  cidr_keys = sort(keys(local.cidr_all))
  cidr_overlaps = flatten([
    for i, a in local.cidr_keys : [
      for b in slice(local.cidr_keys, i + 1, length(local.cidr_keys)) : "${a} (${local.cidr_all[a]}) overlaps ${b} (${local.cidr_all[b]})"
      # AWS VPCs are meant to sit inside the AWS supernet; overlap among them is
      # still checked pairwise.
      if !(contains(["aws.network.top_cidr"], a) && contains(keys(local.cidr_aws_ranges), b)) &&
      !(contains(["aws.network.top_cidr"], b) && contains(keys(local.cidr_aws_ranges), a)) &&
      !(contains(keys(local.cidr_onprem_ranges), a) && contains(keys(local.cidr_onprem_ranges), b)) &&
      cidrhost("${split("/", local.cidr_all[a])[0]}/${min(tonumber(split("/", local.cidr_all[a])[1]), tonumber(split("/", local.cidr_all[b])[1]))}", 0) ==
      cidrhost("${split("/", local.cidr_all[b])[0]}/${min(tonumber(split("/", local.cidr_all[a])[1]), tonumber(split("/", local.cidr_all[b])[1]))}", 0)
    ]
  ])
  # Fixed AWS VPC ranges outside the AWS supernet (top_cidr) are not covered by
  # the transit gateway's top_cidr routes.
  cidr_outside_aws_top = local.cidr_aws_top == null || !can(cidrnetmask(coalesce(local.cidr_aws_top, "x"))) ? [] : [
    for k, c in local.cidr_aws_ranges : "${k} (${c}) is outside aws.network.top_cidr (${local.cidr_aws_top})"
    if tonumber(split("/", c)[1]) < tonumber(split("/", local.cidr_aws_top)[1]) ||
    cidrhost("${split("/", c)[0]}/${split("/", local.cidr_aws_top)[1]}", 0) != cidrhost(local.cidr_aws_top, 0)
  ]
  # Explicit IPAM allocation (the aws-workload default) fails at apply when the
  # block is outside the home-region pool, so check it here. The static hub
  # CIDRs (inspection, egress) may sit outside the pool: IPAM cannot allocate a
  # range outside the pool, so they cannot conflict there. They stay in the
  # overlap check above.
  cidr_aws_home_region = try(tostring(local.lz.org.regions.aws), "eu-west-2")

  # Every CIDR provisioned into a regional pool: aws.network.regional_cidrs
  # (the home region falls back to 10.64.0.0/12) and
  # aws.network.regional_additional_cidrs. aws-network reserves the static hub
  # ranges and allocates workload VPCs from these.
  cidr_pool_ranges = local.enable_aws ? merge(
    { for r, c in try({ for r, c in local.lz.aws.network.regional_cidrs : r => tostring(c) }, {}) : "aws.network.regional_cidrs.${r}" => c },
    try(local.lz.aws.network.regional_cidrs[local.cidr_aws_home_region], null) == null ? { "aws.network.regional_cidrs.${local.cidr_aws_home_region}" = "10.64.0.0/12" } : {},
    merge([
      for r, cs in try({ for r, cs in local.lz.aws.network.regional_additional_cidrs : r => cs }, {}) :
      { for i, c in cs : "aws.network.regional_additional_cidrs.${r}[${i}]" => tostring(c) }
    ]...),
  ) : {}
  cidr_pool_valid = { for k, c in local.cidr_pool_ranges : k => c if can(cidrnetmask(c)) }
  cidr_pool_keys  = sort(keys(local.cidr_pool_valid))

  # The home-region pool CIDRs: the regional CIDR first, then the additional ones.
  cidr_aws_pools = concat(
    [for k in local.cidr_pool_keys : local.cidr_pool_valid[k] if k == "aws.network.regional_cidrs.${local.cidr_aws_home_region}"],
    [for k in local.cidr_pool_keys : local.cidr_pool_valid[k] if startswith(k, "aws.network.regional_additional_cidrs.${local.cidr_aws_home_region}[")],
  )

  # An additional pool CIDR must sit inside top_cidr and overlap no other pool
  # CIDR (IPAM rejects an overlapping CIDR in the same scope at apply).
  cidr_pool_issues = concat(
    local.cidr_aws_top == null || !can(cidrnetmask(coalesce(local.cidr_aws_top, "x"))) ? [] : [
      for k in local.cidr_pool_keys : "${k} (${local.cidr_pool_valid[k]}) is outside aws.network.top_cidr (${local.cidr_aws_top})"
      if startswith(k, "aws.network.regional_additional_cidrs.") && (
        tonumber(split("/", local.cidr_pool_valid[k])[1]) < tonumber(split("/", local.cidr_aws_top)[1]) ||
        cidrhost("${split("/", local.cidr_pool_valid[k])[0]}/${split("/", local.cidr_aws_top)[1]}", 0) != cidrhost(local.cidr_aws_top, 0)
      )
    ],
    flatten([
      for i, a in local.cidr_pool_keys : [
        for b in slice(local.cidr_pool_keys, i + 1, length(local.cidr_pool_keys)) : "${a} (${local.cidr_pool_valid[a]}) overlaps ${b} (${local.cidr_pool_valid[b]})"
        if cidrhost("${split("/", local.cidr_pool_valid[a])[0]}/${min(tonumber(split("/", local.cidr_pool_valid[a])[1]), tonumber(split("/", local.cidr_pool_valid[b])[1]))}", 0) ==
        cidrhost("${split("/", local.cidr_pool_valid[b])[0]}/${min(tonumber(split("/", local.cidr_pool_valid[a])[1]), tonumber(split("/", local.cidr_pool_valid[b])[1]))}", 0)
      ]
    ]),
  )

  cidr_outside_aws_pool = length(local.cidr_aws_pools) == 0 ? [] : [
    for k, c in local.cidr_aws_ranges : "${k} (${c}) is outside the ${local.cidr_aws_home_region} regional pool (${join(", ", local.cidr_aws_pools)})"
    if startswith(k, "aws.workload_environments.") && !anytrue([
      for p in local.cidr_aws_pools :
      tonumber(split("/", c)[1]) >= tonumber(split("/", p)[1]) &&
      cidrhost("${split("/", c)[0]}/${split("/", p)[1]}", 0) == cidrhost(p, 0)
    ])
  ]
}
