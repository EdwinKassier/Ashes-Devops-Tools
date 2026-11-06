# tfc-admin: declare the whole Terraform Cloud workspace layer as code.
#
# Workspaces, projects, VCS wiring + trigger patterns, explicit remote-state
# sharing, health assessments, dynamic-credential env vars, shared variable sets,
# least-privilege team access and an optional OPA policy set are derived from the same
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
    # Security-team workspace: org IAM deny policies (admin containment).
    "gcp-guardrails" = { dir = "envs/gcp/guardrails", cloud = "gcp", desc = "GCP org IAM deny policies (security team)", tags = ["cloud:gcp", "layer:control-plane", "owner:security"] }
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
  # Dedicated per-workspace management roles (aws-security, aws-backup) from
  # aws-organization; they replace the shared phase-0 role for those roots.
  aws_output_mgmt_plan_roles  = try(tomap(local.aws_organization_outputs.tfc_management_plan_role_arns), {})
  aws_output_mgmt_apply_roles = try(tomap(local.aws_organization_outputs.tfc_management_apply_role_arns), {})

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

  # Per workspace: the dedicated management role pair when aws-organization
  # created one, else the shared phase-0 role (aws-organization always uses it).
  aws_management_defaults = {
    for ws in local.aws_management_workspaces : ws => {
      plan  = try(local.aws_output_mgmt_plan_roles[ws], var.aws_management_plan_role_arn)
      apply = try(local.aws_output_mgmt_apply_roles[ws], var.aws_management_apply_role_arn)
    } if contains(local.workspace_names, ws) && lookup(local.aws_aliases_complete, ws, true) &&
    (try(local.aws_output_mgmt_plan_roles[ws], var.aws_management_plan_role_arn) != null)
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
      for ws in keys(local.saas) : ws => {
        stack = { value = trimprefix(ws, "saas-"), category = "terraform", hcl = false, sensitive = false, description = "SaaS stack key in saas.stacks (derived from the workspace name)." }
      }
    },
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
  # The committed file must not steer credentials or the CLI: dynamic-credential
  # env vars (TFC_*), CLI argument injection (TF_CLI_ARGS*), provider auth env
  # vars, or Terraform's own controls. tfc-admin derives the legitimate ones.
  file_reserved_entries = flatten([
    for ws, vars in local.file_workspace_variables : [
      for k, v in vars : "${ws}.${k}"
      if v.category == "env" && can(regex("^(TFC_|TF_CLI_ARGS|TF_VAR_|TF_WORKSPACE|TF_LOG|AWS_|GOOGLE_|CLOUDSDK_|SUPABASE_|VERCEL_)", k))
    ]
  ])
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
  # One project per cloud; with split_workload_projects the gcp/aws workload
  # workspaces move to <prefix><cloud>-workloads so access is granted per project.
  # gcp-guardrails always gets its own project (security team only).
  workspace_project_key = {
    for k, w in local.workspaces : k => (
      contains(local.guardrails_workspaces, k) ? "guardrails" : (
        local.split_workload_projects && contains(["gcp", "aws"], w.cloud) && !local.is_control_plane[k] ? "${w.cloud}-workloads" : w.cloud
      )
    )
  }
  project_keys = var.enable_projects ? toset(distinct(values(local.workspace_project_key))) : toset([])

  # Projects that hold at least one control-plane / bootstrap workspace. The
  # guardrails project is not among them: its access model is its own.
  control_plane_projects = toset([for k, p in local.workspace_project_key : p if local.is_control_plane[k] && contains(local.project_keys, p) && p != "guardrails"])

  # Every project except the security-only guardrails project.
  shared_access_projects = setsubtract(local.project_keys, ["guardrails"])

  # ── Team access ────────────────────────────────────────────────
  # The broad platform team never gets fixed write on a control-plane project:
  # write would let one member edit a control-plane variable (containment /
  # break-glass inputs) and confirm the apply alone. There it gets custom access
  # (runs = platform_team_control_plane_runs, variables read-only), and only the
  # separate approvers team may confirm applies. Workload-only projects keep
  # fixed write; workload workspaces sharing a project with the control plane
  # get write through a workspace-level grant (TFC permissions are additive).
  platform_custom_access = {
    runs           = var.platform_team_control_plane_runs
    variables      = "read"
    state_versions = "read-outputs"
    sentinel_mocks = "none"
    locking        = false
  }
  # Security team on the guardrails project: queue plans and confirm applies
  # (runs = apply) and lock the workspace; variables stay read-only, like every
  # control-plane grant here ("Variables belong in code", README), so the deny
  # policies change only through a reviewed config/landing-zone.yaml.
  security_custom_access = {
    runs           = "apply"
    variables      = "read"
    state_versions = "read"
    sentinel_mocks = "none"
    locking        = true
  }
  approvers_custom_access = {
    runs           = "apply"
    variables      = "read"
    state_versions = "read"
    sentinel_mocks = "none"
    locking        = true
  }

  # ── Guardrails (security team only) ──────────────────────────
  # gcp-guardrails applies the org IAM deny policies that contain the platform's
  # own automation identity. It sits in its own project where ONLY the security
  # team has access (queue, confirm and discard runs): no platform,
  # approvers or viewer grant. Organization owners keep their implicit access,
  # and tfc-admin itself can still repoint the workspace, so separation of
  # duties also rests on CODEOWNERS for envs/tfc-admin/** (docs/known-gaps.md).
  guardrails_workspaces = local.enable_gcp ? ["gcp-guardrails"] : []
  guardrails_project    = contains(local.project_keys, "guardrails")

  # Workspaces that must never apply without a human confirmation, whatever a
  # future auto-apply setting does for the others.
  never_auto_apply_workspaces = concat(local.guardrails_workspaces, [var.tfc_admin_workspace_name])

  team_project_access = merge(
    var.platform_team_id == null ? {} : {
      for p in local.shared_access_projects : "${p}/platform" => {
        project = p
        team_id = var.platform_team_id
        access  = contains(local.control_plane_projects, p) ? "custom" : "write"
        custom  = contains(local.control_plane_projects, p) ? local.platform_custom_access : null
      }
    },
    var.control_plane_approvers_team_id == null ? {} : {
      for p in local.control_plane_projects : "${p}/approvers" => {
        project = p
        team_id = var.control_plane_approvers_team_id
        access  = "custom"
        custom  = local.approvers_custom_access
      }
    },
    {
      for pair in setproduct(tolist(local.shared_access_projects), var.viewer_team_ids) :
      "${pair[0]}/${pair[1]}" => { project = pair[0], team_id = pair[1], access = "read", custom = null }
    },
    var.security_team_id == null || !local.guardrails_project ? {} : {
      "guardrails/security" = { project = "guardrails", team_id = var.security_team_id, access = "custom", custom = local.security_custom_access }
    },
  )

  # Workload workspaces that share a project with the control plane.
  platform_workspace_write = var.platform_team_id == null ? toset([]) : toset([
    for k, p in local.workspace_project_key : k if !local.is_control_plane[k] && contains(local.control_plane_projects, p)
  ])

  # ── Speculative plans ──────────────────────────────────────────
  speculative_disabled = setunion(
    toset(var.speculative_disabled_workspaces),
    toset(local.guardrails_workspaces),
    var.disable_speculative_on_production ? local.production_workloads : toset([]),
    var.disable_speculative_on_saas ? toset(keys(local.saas)) : toset([]),
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
      condition     = length(local.file_reserved_entries) == 0
      error_message = "workspace_variables_file sets reserved environment variables: ${join(", ", local.file_reserved_entries)}. Dynamic-credential (TFC_*), CLI (TF_CLI_ARGS*, TF_*) and provider-auth env vars are derived by tfc-admin or set write-only via workspace_variables, never from the committed file."
    }
    precondition {
      condition     = length(local.file_sensitive_entries) == 0
      error_message = "workspace_variables_file must not hold sensitive values (it is committed): ${join(", ", local.file_sensitive_entries)}. Set secrets via workspace_variables (write-only) instead."
    }
    precondition {
      condition     = var.control_plane_approvers_team_id == null || var.control_plane_approvers_team_id != var.platform_team_id
      error_message = "control_plane_approvers_team_id must differ from platform_team_id: the approvers team exists so the people who change the control plane are not the ones who approve its apply."
    }
    precondition {
      condition     = var.security_team_id == null || (var.security_team_id != var.platform_team_id && var.security_team_id != var.control_plane_approvers_team_id)
      error_message = "security_team_id must differ from platform_team_id and control_plane_approvers_team_id: the security team alone applies gcp-guardrails, which contains the platform's own automation identity."
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

  # Custom grants: no project-settings, team or variable-set management, and no
  # workspace create/delete/move, run tasks or policy overrides.
  dynamic "project_access" {
    for_each = each.value.custom == null ? [] : [each.value.custom]
    content {
      settings      = "read"
      teams         = "none"
      variable_sets = "read"
    }
  }

  dynamic "workspace_access" {
    for_each = each.value.custom == null ? [] : [each.value.custom]
    content {
      runs             = workspace_access.value.runs
      variables        = workspace_access.value.variables
      state_versions   = workspace_access.value.state_versions
      sentinel_mocks   = workspace_access.value.sentinel_mocks
      locking          = workspace_access.value.locking
      create           = false
      delete           = false
      move             = false
      run_tasks        = false
      policy_overrides = false
    }
  }
}

# Platform-team write on workload workspaces that live in a control-plane
# project (single project per cloud); additive to the custom project grant.
resource "tfe_team_access" "platform_workload" {
  for_each = local.platform_workspace_write

  team_id      = var.platform_team_id
  workspace_id = module.workspace[each.key].id
  access       = "write"
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
  project_id        = var.enable_projects ? tfe_project.this[local.workspace_project_key[each.key]].id : null

  vcs_repo              = local.vcs_repo
  file_triggers_enabled = true
  trigger_patterns      = concat(["${each.value.dir}/**"], local.module_paths[each.value.cloud])

  # Control plane and production workloads: no automatic speculative PR plans
  # (a PR's code would run as the plan identity); no UI destroy plans on the
  # control plane. auto_apply stays false everywhere today; the
  # never_auto_apply_workspaces (gcp-guardrails, tfc-admin) must stay false
  # under any future auto-apply setting.
  speculative_enabled = !contains(local.speculative_disabled, each.key)
  allow_destroy_plan  = !local.is_control_plane[each.key]
  auto_apply          = false

  assessments_enabled = var.enable_health_assessments

  # Settings (execution mode + remote-state consumers) are declared below so a
  # workspace can list its sibling workspaces as consumers without a cycle.
  manage_settings = false

  variables        = local.workspace_vars[each.key]
  variable_set_ids = { common = tfe_variable_set.common.id }

  # Control-plane and bootstrap workspaces alert on failed runs;
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

# Without a security team the guardrails project has no team grant (only
# organization owners can run gcp-guardrails); without projects there is no
# separate project at all.
check "guardrails_project_has_security_team" {
  assert {
    condition     = length(local.guardrails_workspaces) == 0 || (local.guardrails_project && var.security_team_id != null)
    error_message = "gcp-guardrails is managed but ${local.guardrails_project ? "security_team_id is null: no team can run it (organization owners only). Create a security team and set security_team_id." : "enable_projects = false: it shares the default project instead of a security-only one. Set enable_projects = true and security_team_id."}"
  }
}

# Adopt the hand-created tfc-admin workspace instead of creating a duplicate.
# An unmanaged tfc-admin workspace keeps TFC's default speculative_enabled =
# true. With a VCS connection that hands every PR a plan that can read the
# org-admin TFE_TOKEN, so warn on every plan until it is adopted.
check "tfc_admin_workspace_hardened" {
  assert {
    condition     = var.manage_tfc_admin_workspace || local.vcs_repo == null
    error_message = "manage_tfc_admin_workspace = false while vcs_repo is set: the hand-created tfc-admin workspace keeps speculative PR plans ON, so a pull request's plan can read its org-admin TFE_TOKEN. Set manage_tfc_admin_workspace = true, or disable speculative plans on it by hand."
  }
}

import {
  for_each = var.manage_tfc_admin_workspace && var.import_tfc_admin_workspace ? toset([var.tfc_admin_workspace_name]) : toset([])
  to       = module.workspace[each.key].tfe_workspace.this
  id       = "${local.tfc_organization}/${each.key}"
}

# ── Optional OPA policy set (mixed mandatory / advisory) ───────────────────
# Sourced from policies/opa/ in this repo via VCS. Enforcement level is set per
# policy in policies/opa/policies.hcl: 10 mandatory (public exposure, identity,
# encryption) + 4 advisory. The set is NOT overridable by default
# (policy_set_overridable = false), so a mandatory failure is a hard stop that
# no "Manage Policy Overrides" user can wave through; advisory results never
# block. Requires a PAID HCP Terraform tier with policy enforcement (not the
# free tier) and a vcs_repo.
resource "tfe_policy_set" "opa" {
  count = var.enable_policy_sets ? 1 : 0

  organization        = local.tfc_organization
  name                = "${local.project_name_prefix}opa-guardrails"
  description         = "Landing-zone OPA guardrails from policies/opa (mixed mandatory/advisory; see policies.hcl)."
  kind                = "opa"
  overridable         = var.policy_set_overridable
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

# ── gcp-bootstrap: immutable workspace IDs for the WIF bindings ─────────────
# gcp-bootstrap binds each gcp-* workspace's plan/apply SA by workspace ID when
# it knows the ID (by name otherwise, which a production estate rejects). The
# IDs only exist once this root has created the workspaces, so it writes them
# onto gcp-bootstrap here (a separate resource, so the workspace module does not
# depend on its own IDs). The local phase-0 apply runs in local execution mode,
# which ignores workspace variables: use output.gcp_bootstrap_tfvars there.
locals {
  gcp_bootstrap_workspace_ids = {
    for ws, m in module.workspace : ws => m.id if startswith(ws, "gcp-")
  }
  set_gcp_bootstrap_workspace_ids = (
    var.set_gcp_bootstrap_workspace_ids &&
    contains(keys(local.workspaces), "gcp-bootstrap") &&
    !contains(keys(lookup(local.workspace_vars, "gcp-bootstrap", {})), "tfc_workspace_ids")
  )
}

resource "tfe_variable" "gcp_bootstrap_workspace_ids" {
  count = local.set_gcp_bootstrap_workspace_ids ? 1 : 0

  workspace_id = module.workspace["gcp-bootstrap"].id
  key          = "tfc_workspace_ids"
  value        = jsonencode(local.gcp_bootstrap_workspace_ids)
  category     = "terraform"
  hcl          = true
  description  = "TFC workspace name -> immutable ID for every gcp-* workspace (set by tfc-admin), so gcp-bootstrap binds WIF by ID, never by squattable name."
}

# ── Run triggers along the dependency DAG ───────────────────────────────────
# A successful apply upstream queues a run downstream, so a change to
# gcp-projects (say) is followed by a plan of gcp-network-hub and every
# gcp-workload-<env> instead of waiting for someone to remember. Downstream
# auto_apply stays false: the triggered run is a plan awaiting confirmation.
# Only the direct edges (the DAG's transitive reduction), so a workload is
# queued once per upstream change, not once per ancestor.
locals {
  run_trigger_edges = {
    "gcp-organization"    = ["gcp-bootstrap"]
    "gcp-projects"        = ["gcp-organization"]
    "gcp-network-hub"     = ["gcp-projects"]
    "aws-security"        = ["aws-organization"]
    "aws-network"         = ["aws-organization"]
    "aws-identity"        = ["aws-organization"]
    "aws-shared-services" = ["aws-organization"]
    "aws-backup"          = ["aws-organization"]
  }
  run_trigger_pairs = var.enable_run_triggers ? merge(
    merge([
      for downstream, sources in local.run_trigger_edges : {
        for src in sources : "${src}->${downstream}" => { source = src, downstream = downstream }
        if contains(keys(local.workspaces), src) && contains(keys(local.workspaces), downstream)
      }
    ]...),
    {
      for ws in local.gcp_workload_names : "gcp-network-hub->${ws}" => { source = "gcp-network-hub", downstream = ws }
      if contains(keys(local.workspaces), "gcp-network-hub")
    },
    merge([
      for ws in local.aws_workload_names : {
        for src in ["aws-network", "aws-security"] : "${src}->${ws}" => { source = src, downstream = ws }
        if contains(keys(local.workspaces), src)
      }
    ]...),
  ) : {}
}

resource "tfe_run_trigger" "dag" {
  for_each = local.run_trigger_pairs

  workspace_id  = module.workspace[each.value.downstream].id
  sourceable_id = module.workspace[each.value.source].id
}
