# tfc-admin: declare the whole Terraform Cloud workspace layer as code (audit C3).
#
# Workspaces, projects, VCS wiring + trigger patterns, explicit remote-state
# sharing, health assessments, dynamic-credential env vars, shared variable sets,
# team access and an optional OPA policy set are derived from the same
# config/landing-zone.yaml the cloud roots read (config.tf), so a new
# environment or cloud is a reviewed one-file change, not console clicking. Apply it FIRST (the tfc-admin workspace
# itself is created by hand once, then it manages all the others; optionally it
# adopts itself via manage_tfc_admin_workspace). It never applies cloud
# infrastructure and declares no cloud provider.
#
# Cloud selection: enable_gcp / enable_aws / enable_saas (else gcp/aws/saas
# .enabled in the config file; all default false; at least one must be enabled)
# decide which workspaces exist, so an AWS-only or SaaS-only adopter gets no
# dead gcp-* workspaces.

locals {
  # Module domains each root consumes. A module-only PR must trigger a plan on
  # every workspace whose root composes that domain (trigger_patterns replace
  # the working-directory default, so the root's own dir is listed too).
  module_paths = {
    gcp      = ["modules/gcp/**"]
    aws      = ["modules/aws/**"]
    saas     = ["modules/saas/**", "modules/supabase/**", "modules/vercel/**"]
    platform = ["modules/tfc/**"]
  }

  gcp_control_plane = local.enable_gcp ? {
    "gcp-bootstrap"    = { dir = "envs/gcp/bootstrap", cloud = "gcp", desc = "GCP phase-0: admin project, Terraform admin SA, WIF pools", tags = ["cloud:gcp", "layer:bootstrap"] }
    "gcp-organization" = { dir = "envs/gcp/organization", cloud = "gcp", desc = "GCP org: folders, org policy, KMS, audit, billing", tags = ["cloud:gcp", "layer:control-plane"] }
    "gcp-projects"     = { dir = "envs/gcp/projects", cloud = "gcp", desc = "GCP host/spoke projects", tags = ["cloud:gcp", "layer:control-plane"] }
    "gcp-network-hub"  = { dir = "envs/gcp/network-hub", cloud = "gcp", desc = "GCP hub VPC, DNS anchor, hub VPC-SC", tags = ["cloud:gcp", "layer:control-plane"] }
  } : {}

  gcp_workloads = local.enable_gcp ? {
    for env in local.gcp_environment_keys :
    "gcp-workload-${env}" => { dir = "envs/gcp/workload", cloud = "gcp", desc = "GCP ${env} workload", tags = ["cloud:gcp", "layer:workload", "env:${env}"] }
  } : {}

  aws_control_plane = local.enable_aws ? {
    "aws-organization"    = { dir = "envs/aws/organization", cloud = "aws", desc = "AWS org, SCP/RCP, account factory", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-security"        = { dir = "envs/aws/security", cloud = "aws", desc = "AWS security baseline + log archive", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-network"         = { dir = "envs/aws/network", cloud = "aws", desc = "AWS shared networking (TGW/IPAM)", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-identity"        = { dir = "envs/aws/identity", cloud = "aws", desc = "AWS IAM Identity Center", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-shared-services" = { dir = "envs/aws/shared-services", cloud = "aws", desc = "AWS shared platform services", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-backup"          = { dir = "envs/aws/backup", cloud = "aws", desc = "AWS centralized backup", tags = ["cloud:aws", "layer:control-plane"] }
  } : {}

  aws_workloads = local.enable_aws ? {
    for env in keys(local.aws_environments) :
    "aws-workload-${env}" => { dir = "envs/aws/workload", cloud = "aws", desc = "AWS ${env} workload", tags = ["cloud:aws", "layer:workload", "env:${env}"] }
  } : {}

  saas = local.enable_saas ? {
    for name in local.saas_workspaces :
    "saas-${name}" => { dir = "envs/saas", cloud = "saas", desc = "SaaS ${name} (Supabase/Vercel)", tags = ["cloud:saas", "layer:workload"] }
  } : {}

  # Optional self-management of the hand-created tfc-admin workspace (adopted via
  # the import block below, never created).
  platform = var.manage_tfc_admin_workspace ? {
    (var.tfc_admin_workspace_name) = { dir = "envs/tfc-admin", cloud = "platform", desc = "TFC workspace layer (this root)", tags = ["cloud:tfc", "layer:control-plane"] }
  } : {}

  workspaces = merge(
    local.gcp_control_plane,
    local.gcp_workloads,
    local.aws_control_plane,
    local.aws_workloads,
    local.saas,
    local.platform,
  )

  workspace_names = toset(keys(local.workspaces))

  is_control_plane = {
    for k, w in local.workspaces :
    k => contains(w.tags, "layer:control-plane") || contains(w.tags, "layer:bootstrap")
  }

  # ── Remote-state consumer graph ───────────────────────────────────────────
  # Derived from the data "terraform_remote_state" blocks in envs/**: producer
  # => the workspaces that read it. global_remote_state is false everywhere, so
  # only these edges (plus extra_remote_state_consumers) can read a state file.
  gcp_workload_names = keys(local.gcp_workloads)
  aws_workload_names = keys(local.aws_workloads)

  base_consumers = {
    "gcp-bootstrap"    = ["gcp-organization", "gcp-projects"]
    "gcp-organization" = concat(["gcp-projects", "gcp-network-hub"], local.gcp_workload_names)
    "gcp-projects"     = concat(["gcp-network-hub"], local.gcp_workload_names)
    "gcp-network-hub"  = local.gcp_workload_names
    "aws-organization" = concat(["aws-security", "aws-network", "aws-identity", "aws-shared-services", "aws-backup"], local.aws_workload_names)
    "aws-network"      = local.aws_workload_names
    "aws-security"     = local.aws_workload_names
  }

  # tfc-admin reads gcp-bootstrap / aws-organization outputs (tfe_outputs) only
  # when the *_outputs_from_tfc toggles are on; grant it read access then.
  tfc_admin_reads = compact([
    var.gcp_bootstrap_outputs_from_tfc ? "gcp-bootstrap" : "",
    var.aws_organization_outputs_from_tfc ? "aws-organization" : "",
  ])
  tfc_admin_workspace_id = length(local.tfc_admin_reads) == 0 ? null : (
    var.manage_tfc_admin_workspace ? module.workspace[var.tfc_admin_workspace_name].id : data.tfe_workspace.tfc_admin[0].id
  )

  consumer_names = {
    for producer in local.workspace_names : producer => distinct([
      for c in concat(
        lookup(local.base_consumers, producer, []),
        lookup(var.extra_remote_state_consumers, producer, []),
      ) : c if contains(local.workspace_names, c)
    ])
  }

  consumer_ids = {
    for producer, consumers in local.consumer_names : producer => concat(
      [for c in consumers : module.workspace[c].id],
      contains(local.tfc_admin_reads, producer) && !contains(consumers, var.tfc_admin_workspace_name) ? [local.tfc_admin_workspace_id] : [],
    )
  }

  # ── Dynamic provider credentials ──────────────────────────────────────────
  # Explicit input maps win over values read from upstream outputs.
  gcp_bootstrap_outputs = try(data.tfe_outputs.gcp_bootstrap[0].nonsensitive_values, {})

  gcp_workload_provider_name = coalesce(var.gcp_workload_provider_name, try(local.gcp_bootstrap_outputs.tfc_workload_provider_name, null), "unset")

  gcp_plan_sas = merge(
    try(tomap(local.gcp_bootstrap_outputs.tfc_plan_service_accounts), {}),
    var.gcp_plan_service_accounts,
  )
  gcp_apply_sas = merge(
    try(tomap(local.gcp_bootstrap_outputs.tfc_apply_service_accounts), {}),
    var.gcp_apply_service_accounts,
  )

  # Env-var descriptions (shared by every workspace that gets the var).
  credential_env_descriptions = {
    TFC_GCP_PROVIDER_AUTH               = "Enable HCP Terraform GCP dynamic credentials (WIF)."
    TFC_GCP_WORKLOAD_PROVIDER_NAME      = "Full WIF provider resource name (projects/<num>/locations/global/workloadIdentityPools/<pool>/providers/<provider>)."
    TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL  = "Read-only SA impersonated during plan."
    TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL = "SA impersonated during apply."
    TFC_AWS_PROVIDER_AUTH               = "Enable HCP Terraform AWS dynamic credentials (OIDC)."
    TFC_AWS_PLAN_ROLE_ARN               = "Read-only IAM role assumed during plan."
    TFC_AWS_APPLY_ROLE_ARN              = "IAM role assumed during apply."
  }

  # A GCP workspace gets dynamic credentials only when the WIF provider name is
  # known AND it has a plan or apply SA; nothing is set otherwise.
  gcp_credential_env = {
    for ws, w in local.workspaces : ws => {
      for k, v in {
        TFC_GCP_PROVIDER_AUTH               = "true"
        TFC_GCP_WORKLOAD_PROVIDER_NAME      = local.gcp_workload_provider_name
        TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL  = try(local.gcp_plan_sas[ws], null)
        TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL = try(local.gcp_apply_sas[ws], null)
      } : k => { value = v, category = "env", hcl = false, sensitive = false, description = local.credential_env_descriptions[k] } if v != null
    }
    if w.cloud == "gcp" && local.gcp_workload_provider_name != "unset" && (try(local.gcp_plan_sas[ws], null) != null || try(local.gcp_apply_sas[ws], null) != null)
  }

  aws_organization_outputs = try(data.tfe_outputs.aws_organization[0].nonsensitive_values, {})
  aws_output_plan_roles    = try(tomap(local.aws_organization_outputs.tfc_plan_role_arns), {})
  aws_output_apply_roles   = try(tomap(local.aws_organization_outputs.tfc_apply_role_arns), {})

  # Roots whose DEFAULT provider is the management (payer) account. Their default
  # credentials are the phase-0 management-account role, never a member role.
  aws_management_workspaces = ["aws-organization", "aws-security", "aws-backup"]

  # Multi-account roots and their member-account provider aliases (alias name ==
  # aws-organization account key; see envs/aws/{security,backup}/providers.tf).
  # Each alias authenticates directly as that account's tfc-plan / tfc-apply role
  # through a TFC multiple-configuration dynamic credential.
  aws_alias_accounts = {
    "aws-security" = ["security_tooling", "log_archive", "forensics"]
    "aws-backup"   = ["backup"]
  }

  # Single-account workspace => account key. Sources, lowest precedence first:
  # aws-organization's tfc_workspace_bindings (account key => workspace names,
  # inverted), environments[*].aws_account_key for aws-workload-<env>, then
  # var.aws_workspace_account_keys. Management-default roots are excluded: their
  # bindings exist only to trust the alias roles.
  aws_bound_workspaces = {
    for pair in flatten([
      for acct, wss in try(tomap(local.aws_organization_outputs.tfc_workspace_bindings), {}) : [
        for ws in wss : { ws = ws, acct = acct }
      ]
    ]) : pair.ws => pair.acct...
  }
  aws_workspace_accounts = {
    for ws, acct in merge(
      { for ws, accts in local.aws_bound_workspaces : ws => sort(accts)[0] },
      { for env, e in local.aws_environments : "aws-workload-${env}" => e.aws_account_key if e.aws_account_key != null },
      var.aws_workspace_account_keys,
    ) : ws => acct if !contains(local.aws_management_workspaces, ws)
  }

  # Per-alias role pairs for the managed multi-account workspaces: explicit
  # aws_alias_role_arns win over the aws-organization outputs.
  aws_alias_roles = {
    for ws, aliases in local.aws_alias_accounts : ws => {
      for a in aliases : a => {
        plan  = try(var.aws_alias_role_arns[ws][a].plan_role_arn, local.aws_output_plan_roles[a], null)
        apply = try(var.aws_alias_role_arns[ws][a].apply_role_arn, local.aws_output_apply_roles[a], null)
      }
    } if contains(local.workspace_names, ws)
  }
  # A multi-account workspace is credential-complete only when every alias has
  # both roles; the derived management default is withheld until then, because
  # TFC would otherwise inject tfc_aws_dynamic_credentials without the aliases
  # the root's providers index.
  aws_aliases_complete = {
    for ws, aliases in local.aws_alias_roles : ws => alltrue([for r in values(aliases) : r.plan != null && r.apply != null])
  }

  aws_management_defaults = var.aws_management_plan_role_arn == null ? {} : {
    for ws in local.aws_management_workspaces : ws => {
      plan  = var.aws_management_plan_role_arn
      apply = var.aws_management_apply_role_arn
    } if contains(local.workspace_names, ws) && lookup(local.aws_aliases_complete, ws, true)
  }

  aws_plan_roles = merge(
    { for ws, r in local.aws_management_defaults : ws => r.plan },
    {
      for ws, acct in local.aws_workspace_accounts : ws => local.aws_output_plan_roles[acct]
      if try(local.aws_output_plan_roles[acct], null) != null
    },
    var.aws_plan_role_arns,
  )
  aws_apply_roles = merge(
    { for ws, r in local.aws_management_defaults : ws => r.apply },
    {
      for ws, acct in local.aws_workspace_accounts : ws => local.aws_output_apply_roles[acct]
      if try(local.aws_output_apply_roles[acct], null) != null
    },
    var.aws_apply_role_arns,
  )

  # Alias env vars are emitted only for a workspace whose default credentials are
  # set too (a TFC alias configuration without the default one is unusable).
  aws_alias_env = {
    for ws, aliases in local.aws_alias_roles : ws => merge([
      for a, r in aliases : {
        "TFC_AWS_PROVIDER_AUTH_${a}"  = { value = "true", category = "env", hcl = false, sensitive = false, description = "Enable the ${a} AWS dynamic-credential configuration (provider alias aws.${a})." }
        "TFC_AWS_PLAN_ROLE_ARN_${a}"  = { value = r.plan, category = "env", hcl = false, sensitive = false, description = "${a} account tfc-plan role assumed by alias aws.${a} during plan." }
        "TFC_AWS_APPLY_ROLE_ARN_${a}" = { value = r.apply, category = "env", hcl = false, sensitive = false, description = "${a} account tfc-apply role assumed by alias aws.${a} during apply." }
      } if r.plan != null && r.apply != null
    ]...)
    if try(local.aws_plan_roles[ws], null) != null
  }

  aws_credential_env = {
    for ws, w in local.workspaces : ws => merge(
      {
        for k, v in {
          TFC_AWS_PROVIDER_AUTH  = "true"
          TFC_AWS_PLAN_ROLE_ARN  = try(local.aws_plan_roles[ws], null)
          TFC_AWS_APPLY_ROLE_ARN = try(local.aws_apply_roles[ws], null)
        } : k => { value = v, category = "env", hcl = false, sensitive = false, description = local.credential_env_descriptions[k] } if v != null
      },
      lookup(local.aws_alias_env, ws, {}),
    )
    if w.cloud == "aws" && (try(local.aws_plan_roles[ws], null) != null || try(local.aws_apply_roles[ws], null) != null)
  }

  # A multi-account workspace with default credentials but missing alias roles
  # would fail at plan time inside the root; fail here instead.
  aws_incomplete_multi_account = [
    for ws, complete in local.aws_aliases_complete : ws
    if !complete && contains(keys(local.aws_credential_env), ws)
  ]

  # Workload roots declare var.environment; set it from the workspace name so the
  # env is never hand-typed. aws-workload-<env> also gets workload_account_key
  # when environments[env].aws_account_key is set. Overridable via
  # workspace_variables (or the committed workspace_variables_file).
  derived_terraform_vars = merge(
    {
      for ws in local.gcp_workload_names : ws => {
        environment = { value = trimprefix(ws, "gcp-workload-"), category = "terraform", hcl = false, sensitive = false, description = "Environment key (derived from the workspace name)." }
      }
    },
    {
      for ws in local.aws_workload_names : ws => merge(
        { environment = { value = trimprefix(ws, "aws-workload-"), category = "terraform", hcl = false, sensitive = false, description = "Environment key (derived from the workspace name)." } },
        try(local.aws_environments[trimprefix(ws, "aws-workload-")].aws_account_key, null) == null ? {} : {
          workload_account_key = { value = local.aws_environments[trimprefix(ws, "aws-workload-")].aws_account_key, category = "terraform", hcl = false, sensitive = false, description = "aws-organization account key this workload deploys into (environments[*].aws_account_key or aws.workload_environments[*].account_key)." }
        },
      )
    },
  )

  # ── Committed per-workspace variables (VCS-driven runs) ───────────────────
  workspace_variables_file_path = var.workspace_variables_file == null ? null : (
    startswith(var.workspace_variables_file, "/") ? var.workspace_variables_file : "${path.root}/${var.workspace_variables_file}"
  )
  workspace_variables_file_present = local.workspace_variables_file_path != null && fileexists(coalesce(local.workspace_variables_file_path, "/nonexistent"))
  workspace_variables_file_raw     = local.workspace_variables_file_present ? yamldecode(file(local.workspace_variables_file_path)) : {}

  # Normalise each entry: a bare scalar is a string value; a bare list/map is
  # set as an HCL value (JSON is valid HCL); an object with `value` carries the
  # full {value, category, hcl, description} form.
  file_workspace_variables = {
    for ws, vars in try(local.workspace_variables_file_raw.workspaces, {}) : ws => {
      for k, v in vars : k => {
        value       = can(v.value) ? (can(tostring(v.value)) ? tostring(v.value) : jsonencode(v.value)) : (can(tostring(v)) ? tostring(v) : jsonencode(v))
        category    = can(v.value) ? try(v.category, "terraform") : "terraform"
        hcl         = can(v.value) ? try(v.hcl, !can(tostring(v.value))) : !can(tostring(v))
        sensitive   = can(v.value) ? try(v.sensitive, false) : false
        description = can(v.value) ? try(v.description, null) : "Set from ${var.workspace_variables_file}."
        version     = 1
      }
    }
  }
  file_sensitive_entries = flatten([
    for ws, vars in local.file_workspace_variables : [for k, v in vars : "${ws}.${k}" if v.sensitive]
  ])
  file_bad_categories = flatten([
    for ws, vars in local.file_workspace_variables : [for k, v in vars : "${ws}.${k}" if !contains(["terraform", "env"], v.category)]
  ])

  workspace_vars = {
    for ws in local.workspace_names : ws => merge(
      lookup(local.gcp_credential_env, ws, {}),
      lookup(local.aws_credential_env, ws, {}),
      lookup(local.derived_terraform_vars, ws, {}),
      lookup(local.file_workspace_variables, ws, {}),
      lookup(var.workspace_variables, ws, {}),
    )
  }

  # Execution mode: per-workspace override over the global default.
  execution_modes = {
    for ws in local.workspace_names : ws => lookup(var.workspace_execution_modes, ws, var.execution_mode)
  }

  # ── Projects ──────────────────────────────────────────────────────────────
  project_keys = var.enable_projects ? toset(distinct([for w in values(local.workspaces) : w.cloud])) : toset([])

  team_project_access = merge(
    var.platform_team_id == null ? {} : {
      for p in local.project_keys : "${p}/platform" => { project = p, team_id = var.platform_team_id, access = "write" }
    },
    {
      for pair in setproduct(tolist(local.project_keys), var.viewer_team_ids) :
      "${pair[0]}/${pair[1]}" => { project = pair[0], team_id = pair[1], access = "read" }
    },
  )

  # Every input keyed by workspace name must name a managed workspace of the
  # right cloud (a typo would otherwise silently do nothing).
  unknown_workspace_keys = setsubtract(
    toset(concat(
      keys(var.workspace_variables),
      keys(local.file_workspace_variables),
      keys(var.extra_remote_state_consumers),
      flatten(values(var.extra_remote_state_consumers)),
    )),
    local.workspace_names,
  )
  wrong_cloud_credential_keys = concat(
    [for k in concat(keys(var.gcp_plan_service_accounts), keys(var.gcp_apply_service_accounts)) : k if try(local.workspaces[k].cloud, "") != "gcp"],
    [for k in concat(keys(var.aws_plan_role_arns), keys(var.aws_apply_role_arns), keys(var.aws_workspace_account_keys)) : k if try(local.workspaces[k].cloud, "") != "aws"],
    [for k in keys(var.aws_alias_role_arns) : k if !contains(keys(local.aws_alias_roles), k)],
    [for k in keys(var.aws_workspace_account_keys) : k if contains(local.aws_management_workspaces, k)],
  )
  unknown_alias_keys = flatten([
    for ws, aliases in var.aws_alias_role_arns : [for a in keys(aliases) : "${ws}.${a}" if !contains(lookup(local.aws_alias_accounts, ws, []), a)]
  ])
}

# Fail the plan on inputs that reference workspaces this root does not manage.
resource "terraform_data" "input_contract" {
  lifecycle {
    precondition {
      condition     = length(local.unknown_workspace_keys) == 0
      error_message = "workspace_variables / extra_remote_state_consumers reference unmanaged workspaces: ${join(", ", sort(tolist(local.unknown_workspace_keys)))}."
    }
    precondition {
      condition     = length(local.wrong_cloud_credential_keys) == 0
      error_message = "Dynamic-credential maps reference workspaces that are not managed workspaces of that cloud: ${join(", ", distinct(local.wrong_cloud_credential_keys))}."
    }
    precondition {
      condition     = length(var.gcp_plan_service_accounts) + length(var.gcp_apply_service_accounts) == 0 || local.gcp_workload_provider_name != "unset"
      error_message = "gcp_plan_service_accounts/gcp_apply_service_accounts need gcp_workload_provider_name (or gcp_bootstrap_outputs_from_tfc = true)."
    }
    precondition {
      condition     = length(local.unknown_alias_keys) == 0
      error_message = "aws_alias_role_arns names aliases the root does not declare (aws-security: security_tooling, log_archive, forensics; aws-backup: backup): ${join(", ", local.unknown_alias_keys)}."
    }
    precondition {
      condition     = length(local.aws_incomplete_multi_account) == 0
      error_message = "Multi-account AWS workspaces have default credentials but not every alias role (TFC_AWS_*_<alias>): ${join(", ", local.aws_incomplete_multi_account)}. Supply aws_alias_role_arns or aws_organization_outputs_from_tfc, or remove the workspace's explicit aws_plan_role_arns / aws_apply_role_arns."
    }
    precondition {
      condition     = length(local.file_sensitive_entries) == 0
      error_message = "workspace_variables_file must not hold sensitive values (it is committed): ${join(", ", local.file_sensitive_entries)}. Set secrets via workspace_variables (write-only) instead."
    }
    precondition {
      condition     = length(local.file_bad_categories) == 0
      error_message = "workspace_variables_file categories must be terraform or env: ${join(", ", local.file_bad_categories)}."
    }
  }
}

# ── Upstream outputs (second pass of the bootstrap) ─────────────────────────
data "tfe_outputs" "gcp_bootstrap" {
  count        = var.gcp_bootstrap_outputs_from_tfc ? 1 : 0
  organization = local.tfc_organization
  workspace    = "gcp-bootstrap"
}

data "tfe_outputs" "aws_organization" {
  count        = var.aws_organization_outputs_from_tfc ? 1 : 0
  organization = local.tfc_organization
  workspace    = "aws-organization"
}

# The hand-created tfc-admin workspace, looked up only when it must be granted
# read access to an upstream state and is not self-managed.
data "tfe_workspace" "tfc_admin" {
  count        = length(local.tfc_admin_reads) > 0 && !var.manage_tfc_admin_workspace ? 1 : 0
  name         = var.tfc_admin_workspace_name
  organization = local.tfc_organization
}

# ── Projects + team access ──────────────────────────────────────────────────
resource "tfe_project" "this" {
  for_each = local.project_keys

  organization = local.tfc_organization
  name         = local.project_names[each.key]
  description  = "Landing-zone ${each.key} workspaces (managed by tfc-admin)."
}

resource "tfe_team_project_access" "this" {
  for_each = local.team_project_access

  project_id = tfe_project.this[each.value.project].id
  team_id    = each.value.team_id
  access     = each.value.access
}

# ── Shared variable set ─────────────────────────────────────────────────────
# Org-wide values live once in a variable set attached to every managed
# workspace, instead of being copied onto each one. Workspace variables still
# override set values (priority = false).
resource "tfe_variable_set" "common" {
  organization = local.tfc_organization
  name         = "${local.project_name_prefix}common"
  description  = "Values shared by every landing-zone workspace (managed by tfc-admin)."
}

resource "tfe_variable" "common" {
  for_each = merge(
    { tfc_organization = { value = local.tfc_organization, category = "terraform", hcl = false, sensitive = false, description = "TFC organization (remote-state reads).", version = 1 } },
    var.common_workspace_variables,
  )

  variable_set_id = tfe_variable_set.common.id
  key             = each.key
  # Sensitive values are written write-only (never stored in tfc-admin state).
  value            = each.value.sensitive ? null : each.value.value
  value_wo         = each.value.sensitive ? each.value.value : null
  value_wo_version = each.value.sensitive ? each.value.version : null
  category         = each.value.category
  hcl              = each.value.hcl
  sensitive        = each.value.sensitive
  description      = each.value.description
}

# ── Workspaces ──────────────────────────────────────────────────────────────
module "workspace" {
  source   = "../../modules/tfc/workspace"
  for_each = local.workspaces

  name              = each.key
  organization      = local.tfc_organization
  description       = each.value.desc
  working_directory = each.value.dir
  tag_names         = each.value.tags
  terraform_version = var.terraform_version
  project_id        = var.enable_projects ? tfe_project.this[each.value.cloud].id : null

  vcs_repo              = local.vcs_repo
  file_triggers_enabled = true
  trigger_patterns      = concat(["${each.value.dir}/**"], local.module_paths[each.value.cloud])

  # Control plane: no automatic speculative PR plans, no UI destroy plans.
  speculative_enabled = !contains(var.speculative_disabled_workspaces, each.key)
  allow_destroy_plan  = !local.is_control_plane[each.key]

  assessments_enabled = var.enable_health_assessments

  # Settings (execution mode + remote-state consumers) are declared below so a
  # workspace can list its sibling workspaces as consumers without a cycle.
  manage_settings = false

  variables        = local.workspace_vars[each.key]
  variable_set_ids = { common = tfe_variable_set.common.id }

  # Control-plane and bootstrap workspaces alert on failed runs (audit M-ops);
  # workload workspaces use the separate workload channel (both default empty).
  notifications = local.is_control_plane[each.key] ? var.control_plane_notifications : var.workload_notifications
}

# Remote-state sharing: global_remote_state is false on every workspace and only
# the explicit consumer graph (local.consumer_ids) may read a state file.
resource "tfe_workspace_settings" "this" {
  for_each = local.workspaces

  workspace_id              = module.workspace[each.key].id
  execution_mode            = local.execution_modes[each.key]
  agent_pool_id             = local.execution_modes[each.key] == "agent" ? var.agent_pool_id : null
  global_remote_state       = false
  remote_state_consumer_ids = local.consumer_ids[each.key]
}

# Adopt the hand-created tfc-admin workspace instead of creating a duplicate.
import {
  for_each = var.manage_tfc_admin_workspace && var.import_tfc_admin_workspace ? toset([var.tfc_admin_workspace_name]) : toset([])
  to       = module.workspace[each.key].tfe_workspace.this
  id       = "${local.tfc_organization}/${each.key}"
}

# ── Optional OPA policy set (mixed mandatory / advisory) ───────────────────
# Sourced from policies/opa/ in this repo via VCS. Enforcement level is set per
# policy in policies/opa/policies.hcl: 7 mandatory (public exposure, identity,
# encryption) + 3 advisory. The set is overridable, so a mandatory failure can
# be overridden by a user with "Manage Policy Overrides". Requires a PAID HCP
# Terraform tier with policy enforcement (not the free tier) and a vcs_repo.
resource "tfe_policy_set" "opa" {
  count = var.enable_policy_sets ? 1 : 0

  organization        = local.tfc_organization
  name                = "${local.project_name_prefix}opa-guardrails"
  description         = "Landing-zone OPA guardrails from policies/opa (mixed mandatory/advisory; see policies.hcl)."
  kind                = "opa"
  overridable         = true
  policy_tool_version = var.opa_version
  policies_path       = "policies/opa"
  workspace_ids       = [for k in sort(keys(module.workspace)) : module.workspace[k].id]

  dynamic "vcs_repo" {
    for_each = local.vcs_repo == null ? [] : [local.vcs_repo]
    content {
      identifier                 = vcs_repo.value.identifier
      branch                     = vcs_repo.value.branch
      oauth_token_id             = vcs_repo.value.oauth_token_id
      github_app_installation_id = vcs_repo.value.github_app_installation_id
    }
  }

  lifecycle {
    precondition {
      condition     = local.vcs_repo != null
      error_message = "enable_policy_sets = true requires vcs_repo (or org.tfc.vcs_repo in config/landing-zone.yaml): the policy set is sourced from policies/opa in the repo."
    }
  }
}
