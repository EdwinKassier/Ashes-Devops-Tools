variable "tfc_organization" {
  description = "Terraform Cloud organization that owns all the managed workspaces."
  type        = string
}

variable "environments" {
  description = "Application environments to create per-env workload workspaces for (gcp-workload-<env> when enable_gcp, aws-workload-<env> when enable_aws). Keep the keys in sync with the cloud roots' environments map. Optional aws_account_key names the aws-organization account key (accounts / workload_accounts, e.g. workload_dev) the aws-workload-<env> workspace deploys into: it is set as that workspace's workload_account_key variable and selects the tfc-plan/tfc-apply roles read via aws_organization_outputs_from_tfc."
  type = map(object({
    aws_account_key = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.environments) : can(regex("^[a-z][a-z0-9_-]*$", k))])
    error_message = "environments keys must be lowercase alphanumeric with hyphens/underscores (they become workspace names)."
  }
}

variable "enable_gcp" {
  description = "Declare the GCP control-plane (gcp-bootstrap/organization/projects/network-hub) and gcp-workload-<env> workspaces. Default false: opt in per cloud. At least one of enable_gcp / enable_aws / enable_saas must be true."
  type        = bool
  default     = false

  validation {
    condition     = var.enable_gcp || var.enable_aws || var.enable_saas
    error_message = "Enable at least one cloud: set enable_gcp, enable_aws and/or enable_saas to true (a tfc-admin with no cloud declares no workspaces)."
  }
}

variable "enable_aws" {
  description = "Declare the AWS control-plane and aws-workload-<env> workspaces. Default false; set true for an AWS or multi-cloud estate."
  type        = bool
  default     = false
}

variable "enable_saas" {
  description = "Declare one saas-<name> workspace (working dir envs/saas) per saas_workspaces entry. Default false."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_saas || length(var.saas_workspaces) > 0
    error_message = "enable_saas = true requires at least one saas_workspaces entry."
  }
}

variable "saas_workspaces" {
  description = "SaaS workspace name suffixes (saas-<name>). Only used when enable_saas = true."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.saas_workspaces : can(regex("^[a-z0-9][a-z0-9-]*$", n))])
    error_message = "saas_workspaces entries must be lowercase alphanumeric with hyphens."
  }
}

variable "manage_tfc_admin_workspace" {
  description = "Adopt the hand-created tfc-admin workspace (import block) so its triggers, speculative-plan and remote-state settings are codified too. Default false."
  type        = bool
  default     = false
}

variable "import_tfc_admin_workspace" {
  description = "With manage_tfc_admin_workspace, adopt the existing workspace via an import block. Leave true for the adopting apply; it is a no-op afterwards and may be set false."
  type        = bool
  default     = true
}

variable "tfc_admin_workspace_name" {
  description = "Name of the hand-created workspace that runs this root."
  type        = string
  default     = "tfc-admin"
}

variable "execution_mode" {
  description = "Execution mode for every managed workspace: remote (default) or agent (self-hosted agents; set agent_pool_id)."
  type        = string
  default     = "remote"

  validation {
    condition     = contains(["remote", "agent"], var.execution_mode)
    error_message = "execution_mode must be remote or agent (local would skip TFC-held credentials and policy)."
  }
}

variable "workspace_execution_modes" {
  description = <<-EOT
    Per-workspace execution-mode override (workspace name => remote | agent | local),
    merged over execution_mode. Default { gcp-bootstrap = "local" }: the GCP phase-0
    apply runs on the operator's machine with their ADC (TFC holds state only),
    because no GCP credentials exist yet for a remote run. After the second
    bootstrap pass (TFC_GCP_* env vars wired from the gcp-bootstrap outputs), set
    this to {} so gcp-bootstrap also runs remotely. "local" is accepted only for
    the phase-0 workspaces gcp-bootstrap and aws-organization. Names not managed
    here are ignored.
  EOT
  type        = map(string)
  default     = { "gcp-bootstrap" = "local" }

  validation {
    condition     = alltrue([for m in values(var.workspace_execution_modes) : contains(["remote", "local", "agent"], m)])
    error_message = "workspace_execution_modes values must be remote, agent, or local."
  }

  validation {
    condition     = alltrue([for ws, m in var.workspace_execution_modes : m != "local" || contains(["gcp-bootstrap", "aws-organization"], ws)])
    error_message = "execution mode local is only allowed for the phase-0 workspaces gcp-bootstrap and aws-organization (local runs skip TFC-held credentials and policy)."
  }
}

variable "agent_pool_id" {
  description = "Agent pool ID (apool-...) used when execution_mode = agent."
  type        = string
  default     = null
}

variable "speculative_disabled_workspaces" {
  description = "Workspaces that must NOT run automatic speculative plans on pull requests (control plane: a PR must not get a plan with privileged credentials). Names not managed here are ignored."
  type        = list(string)
  default = [
    "gcp-bootstrap", "gcp-organization", "gcp-projects", "gcp-network-hub",
    "aws-organization", "aws-security", "aws-backup", "aws-identity",
    "tfc-admin",
  ]
}

variable "enable_health_assessments" {
  description = "Enable TFC health assessments (native drift detection + continuous validation) on every managed workspace. Requires an HCP Terraform tier that includes them."
  type        = bool
  default     = true
}

variable "extra_remote_state_consumers" {
  description = <<-EOT
    Additional remote-state edges, producer workspace => consumer workspaces, merged
    into the built-in graph derived from the envs/** terraform_remote_state blocks.
    Use for the opt-in cross-cloud seams: a saas-<name> producer read by
    gcp-workload-<env>/aws-workload-<env> (enable_saas_secret_bridge), or a
    gcp-/aws-workload producer read by saas-<name> (cross_cloud_references).
    Every name must be a managed workspace.
  EOT
  type        = map(list(string))
  default     = {}
}

# ── Dynamic provider credentials ─────────────────────────────────────────────

variable "gcp_workload_provider_name" {
  description = "Full WIF provider name for TFC_GCP_WORKLOAD_PROVIDER_NAME (projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>); gcp-bootstrap output tfc_workload_provider_name. Null = not set (or read from gcp-bootstrap when gcp_bootstrap_outputs_from_tfc)."
  type        = string
  default     = null

  validation {
    condition     = var.gcp_workload_provider_name == null || can(regex("^projects/[0-9]+/locations/global/workloadIdentityPools/[a-z0-9-]+/providers/[a-z0-9-]+$", var.gcp_workload_provider_name))
    error_message = "gcp_workload_provider_name must be projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>."
  }
}

variable "gcp_plan_service_accounts" {
  description = "Workspace name => SA email impersonated during PLAN (TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL); gcp-bootstrap output tfc_plan_service_accounts. Empty = not set. Overrides values read via gcp_bootstrap_outputs_from_tfc."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for e in values(var.gcp_plan_service_accounts) : can(regex("^[^@]+@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", e))])
    error_message = "gcp_plan_service_accounts values must be service-account emails (...@<project>.iam.gserviceaccount.com)."
  }
}

variable "gcp_apply_service_accounts" {
  description = "Workspace name => SA email impersonated during APPLY (TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL); gcp-bootstrap output tfc_apply_service_accounts. Must have the same keys as gcp_plan_service_accounts."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for e in values(var.gcp_apply_service_accounts) : can(regex("^[^@]+@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", e))])
    error_message = "gcp_apply_service_accounts values must be service-account emails (...@<project>.iam.gserviceaccount.com)."
  }

  validation {
    condition     = toset(keys(var.gcp_plan_service_accounts)) == toset(keys(var.gcp_apply_service_accounts))
    error_message = "gcp_plan_service_accounts and gcp_apply_service_accounts must have the same workspace keys (a run phase without an SA would fail)."
  }
}

variable "gcp_bootstrap_outputs_from_tfc" {
  description = "Read tfc_workload_provider_name / tfc_plan_service_accounts / tfc_apply_service_accounts from the gcp-bootstrap workspace outputs (tfe_outputs) instead of copying them into variables. Enable only after gcp-bootstrap has applied; grants tfc-admin read on gcp-bootstrap state."
  type        = bool
  default     = false
}

variable "aws_plan_role_arns" {
  description = "Workspace name => IAM role ARN assumed during PLAN (TFC_AWS_PLAN_ROLE_ARN). Empty = not set. Overrides values derived via aws_organization_outputs_from_tfc."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for a in values(var.aws_plan_role_arns) : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", a))])
    error_message = "aws_plan_role_arns values must be IAM role ARNs."
  }
}

variable "aws_apply_role_arns" {
  description = "Workspace name => IAM role ARN assumed during APPLY (TFC_AWS_APPLY_ROLE_ARN). Must have the same keys as aws_plan_role_arns."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for a in values(var.aws_apply_role_arns) : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", a))])
    error_message = "aws_apply_role_arns values must be IAM role ARNs."
  }

  validation {
    condition     = toset(keys(var.aws_plan_role_arns)) == toset(keys(var.aws_apply_role_arns))
    error_message = "aws_plan_role_arns and aws_apply_role_arns must have the same workspace keys."
  }
}

variable "aws_management_plan_role_arn" {
  description = "Management-account (payer) IAM role assumed during PLAN by the workspaces whose default provider is the management account: aws-organization, aws-security and aws-backup (TFC_AWS_PLAN_ROLE_ARN). This is the phase-0 hand-created role (aws-bootstrap runbook, Step 2; StackSets never deploy to the management account). Null = not set. aws_plan_role_arns overrides it per workspace."
  type        = string
  default     = null

  validation {
    condition     = var.aws_management_plan_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.aws_management_plan_role_arn))
    error_message = "aws_management_plan_role_arn must be an IAM role ARN."
  }
}

variable "aws_management_apply_role_arn" {
  description = "Management-account (payer) IAM role assumed during APPLY by aws-organization, aws-security and aws-backup (TFC_AWS_APPLY_ROLE_ARN). Normally the same ARN passed to aws-organization as terraform_run_role_arn. Set together with aws_management_plan_role_arn."
  type        = string
  default     = null

  validation {
    condition     = var.aws_management_apply_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.aws_management_apply_role_arn))
    error_message = "aws_management_apply_role_arn must be an IAM role ARN."
  }

  validation {
    condition     = (var.aws_management_plan_role_arn == null) == (var.aws_management_apply_role_arn == null)
    error_message = "Set aws_management_plan_role_arn and aws_management_apply_role_arn together (a run phase without a role would fail)."
  }
}

variable "aws_alias_role_arns" {
  description = <<-EOT
    Explicit per-alias roles for the multi-account roots (TFC multiple dynamic-credential
    configurations): workspace => provider alias => {plan_role_arn, apply_role_arn},
    set as TFC_AWS_PROVIDER_AUTH_<alias> / TFC_AWS_PLAN_ROLE_ARN_<alias> /
    TFC_AWS_APPLY_ROLE_ARN_<alias>. Aliases: aws-security = security_tooling,
    log_archive, forensics; aws-backup = backup. Overrides the values derived from
    the aws-organization outputs tfc_plan_role_arns / tfc_apply_role_arns (keyed by
    the same account keys) when aws_organization_outputs_from_tfc = true.
  EOT
  type = map(map(object({
    plan_role_arn  = string
    apply_role_arn = string
  })))
  default = {}

  validation {
    condition = alltrue(flatten([for ws in values(var.aws_alias_role_arns) : [
      for r in values(ws) : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", r.plan_role_arn)) && can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", r.apply_role_arn))
    ]]))
    error_message = "aws_alias_role_arns plan_role_arn / apply_role_arn values must be IAM role ARNs."
  }
}

variable "aws_organization_outputs_from_tfc" {
  description = "Derive per-workspace plan/apply role ARNs from the aws-organization outputs tfc_plan_role_arns / tfc_apply_role_arns (keyed by account key) via tfe_outputs, using aws_workspace_account_keys. Grants tfc-admin read on aws-organization state."
  type        = bool
  default     = false
}

variable "aws_workspace_account_keys" {
  description = "Single-account workspace name => aws-organization account key whose tfc-plan/tfc-apply roles the workspace uses as its DEFAULT credentials, e.g. {\"aws-network\" = \"network\"}. Only used with aws_organization_outputs_from_tfc; overrides the mapping derived from tfc_workspace_bindings and environments[*].aws_account_key. The multi-account roots (aws-organization, aws-security, aws-backup) use the management-account role as their default and are not accepted here."
  type        = map(string)
  default     = {}
}

variable "workspace_variables" {
  description = "Per-workspace variables, workspace name => {key => {value, category (terraform|env, default terraform), hcl?, sensitive?, description?, version?}}. Overrides derived values (e.g. environment) and dynamic-credential env vars. Sensitive values are written write-only; increment `version` to rotate."
  type = map(map(object({
    value       = string
    category    = optional(string, "terraform")
    hcl         = optional(bool, false)
    sensitive   = optional(bool, false)
    description = optional(string)
    version     = optional(number, 1)
  })))
  default = {}

  validation {
    condition     = alltrue(flatten([for ws in values(var.workspace_variables) : [for v in values(ws) : contains(["terraform", "env"], v.category)]]))
    error_message = "workspace_variables categories must be terraform or env."
  }
}

variable "workspace_variables_file" {
  description = <<-EOT
    Committed per-workspace Terraform variables for VCS-driven runs (which get no
    local tfvars). Path relative to this root (or absolute); read only if the file
    exists, so the default is a no-op until you create it. YAML shape (see
    config/tfc-workspaces.example.yaml):
      workspaces:
        <workspace>:
          <key>: <scalar>                       # string/number/bool
          <key>: [list] | {map}                 # set as an HCL value
          <key>: {value: ..., category: env, hcl: true, description: ...}
    Entries are merged under workspace_variables (which wins). sensitive = true is
    rejected: secrets never belong in a committed file. Null disables the lookup.
  EOT
  type        = string
  default     = "../../config/tfc-workspaces.yaml"
}

# ── Projects, teams, policy ──────────────────────────────────────────────────

variable "enable_projects" {
  description = "Group workspaces into one TFC project per cloud (<prefix>gcp, <prefix>aws, <prefix>saas, <prefix>platform). Default true. Required for team access."
  type        = bool
  default     = true
}

variable "project_name_prefix" {
  description = "Prefix for TFC project, variable-set and policy-set names."
  type        = string
  default     = "landing-zone-"
}

variable "platform_team_id" {
  description = "TFC team ID (team-...) granted WRITE on every landing-zone project. Null = no grant."
  type        = string
  default     = null

  validation {
    condition     = var.platform_team_id == null || can(regex("^team-[A-Za-z0-9]+$", var.platform_team_id))
    error_message = "platform_team_id must be a TFC team ID (team-...)."
  }
}

variable "viewer_team_ids" {
  description = "TFC team IDs (team-...) granted READ on every landing-zone project."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for t in var.viewer_team_ids : can(regex("^team-[A-Za-z0-9]+$", t))])
    error_message = "viewer_team_ids entries must be TFC team IDs (team-...)."
  }
}

variable "enable_policy_sets" {
  description = "Create an OPA policy set sourced from policies/opa in the VCS repo, attached to every managed workspace. Policies are advisory (see policies/opa/policies.hcl). Requires vcs_repo and a tier with policy enforcement. Default false."
  type        = bool
  default     = false
}

variable "opa_version" {
  description = "OPA version for the policy set. Null = the TFC default (latest)."
  type        = string
  default     = null
}

variable "terraform_version" {
  description = "Terraform version constraint applied to every managed workspace, e.g. ~> 1.9. Null uses the TFC default."
  type        = string
  default     = "~> 1.9"
}

variable "vcs_repo" {
  description = "Optional VCS connection applied to every workspace (and the OPA policy set): {identifier = \"org/repo\", branch = \"main\", oauth_token_id = \"ot-...\"} or github_app_installation_id. Null = API/CLI-driven workspaces."
  type = object({
    identifier                 = string
    branch                     = optional(string, "main")
    oauth_token_id             = optional(string)
    github_app_installation_id = optional(string)
  })
  default = null
}

variable "common_workspace_variables" {
  description = "Org-wide variables placed in the shared <prefix>common variable set (alongside tfc_organization) attached to EVERY managed workspace. Keyed by name: {value, category (terraform|env), hcl?, sensitive?, description?, version?}. Sensitive values are written write-only (never stored in state); increment `version` to rotate. Per-workspace credentials belong in the dynamic-credential maps, not here."
  type = map(object({
    value       = string
    category    = string
    hcl         = optional(bool, false)
    sensitive   = optional(bool, false)
    description = optional(string)
    version     = optional(number, 1)
  }))
  default = {}
}

variable "control_plane_notifications" {
  description = <<-EOT
    Run notifications applied to every control-plane and bootstrap workspace
    (audit M-ops). Default empty. Set a Slack or generic webhook to be alerted when
    a foundational apply fails or needs attention. Entry shape matches
    modules/tfc/workspace var.notifications.
  EOT
  type = map(object({
    destination_type = string
    url              = optional(string)
    token            = optional(string)
    email_user_ids   = optional(list(string), [])
    triggers         = optional(list(string), ["run:errored", "run:needs_attention"])
    enabled          = optional(bool, true)
  }))
  default = {}
}

variable "workload_notifications" {
  description = "Run notifications applied to every workload workspace. Default empty, so workloads do not page the control-plane channel unless opted in. Same entry shape as control_plane_notifications."
  type = map(object({
    destination_type = string
    url              = optional(string)
    token            = optional(string)
    email_user_ids   = optional(list(string), [])
    triggers         = optional(list(string), ["run:errored", "run:needs_attention"])
    enabled          = optional(bool, true)
  }))
  default = {}
}
