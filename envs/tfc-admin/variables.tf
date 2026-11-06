variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns all the managed workspaces. Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", coalesce(var.tfc_organization, local.cfg.tfc_organization, "!unset")))
    error_message = "tfc_organization is unset or invalid: set var.tfc_organization or org.tfc.organization in config/landing-zone.yaml (letters, digits, '-' and '_')."
  }

  validation {
    condition     = coalesce(var.tfc_organization, local.cfg.tfc_organization, "!unset") != "my-org"
    error_message = "tfc_organization is still the config/landing-zone.example.yaml placeholder 'my-org'. Set your Terraform Cloud organization."
  }
}

variable "environments" {
  description = "Application environments to create per-env workload workspaces for (gcp-workload-<env> when enable_gcp, aws-workload-<env> when enable_aws). Null (default) derives them from config/landing-zone.yaml instead: gcp.environments keys for gcp-workload-<env> and aws.workload_environments (with account_key) for aws-workload-<env>, so the environment list is written once. Optional aws_account_key names the aws-organization account key (accounts / workload_accounts, e.g. workload_dev) the aws-workload-<env> workspace deploys into: it is set as that workspace's workload_account_key variable and selects the tfc-plan/tfc-apply roles read via aws_organization_outputs_from_tfc. Optional is_production (else gcp.environments[*].is_production / aws.workload_environments[*].is_production; unset = true only for the keys prod / production) marks a production workload: see disable_speculative_on_production."
  type = map(object({
    aws_account_key = optional(string)
    is_production   = optional(bool)
  }))
  default = null

  validation {
    condition     = alltrue([for k in concat(keys(coalesce(var.environments, {})), local.cfg.gcp_environment_keys, keys(local.cfg.aws_environments)) : can(regex("^[a-z][a-z0-9_-]*$", k))])
    error_message = "environments keys must be lowercase alphanumeric with hyphens/underscores (they become workspace names)."
  }
}

variable "enable_gcp" {
  description = "Declare the GCP control-plane (gcp-bootstrap/organization/projects/network-hub) and gcp-workload-<env> workspaces. Null = gcp.enabled from config/landing-zone.yaml, else false: opt in per cloud. At least one of enable_gcp / enable_aws / enable_saas must be true."
  type        = bool
  default     = null

  validation {
    condition = anytrue([
      var.enable_gcp != null ? var.enable_gcp : coalesce(local.cfg.enable_gcp, false),
      var.enable_aws != null ? var.enable_aws : coalesce(local.cfg.enable_aws, false),
      var.enable_saas != null ? var.enable_saas : coalesce(local.cfg.enable_saas, false),
    ])
    error_message = "Enable at least one cloud: set enable_gcp, enable_aws and/or enable_saas (or gcp/aws/saas .enabled in config/landing-zone.yaml) to true (a tfc-admin with no cloud declares no workspaces)."
  }
}

variable "enable_aws" {
  description = "Declare the AWS control-plane and aws-workload-<env> workspaces. Null = aws.enabled from config/landing-zone.yaml, else false; set true for an AWS or multi-cloud estate."
  type        = bool
  default     = null
}

variable "enable_saas" {
  description = "Declare one saas-<name> workspace (working dir envs/saas) per saas_workspaces entry. Null = saas.enabled from config/landing-zone.yaml, else false."
  type        = bool
  default     = null

  validation {
    condition = !(var.enable_saas != null ? var.enable_saas : coalesce(local.cfg.enable_saas, false)) || length(
      var.saas_workspaces != null ? var.saas_workspaces : coalesce(local.cfg.saas_workspaces, [])
    ) > 0
    error_message = "enable_saas = true requires at least one saas_workspaces entry."
  }
}

variable "saas_workspaces" {
  description = "SaaS workspace name suffixes (saas-<name>). Only used when enable_saas = true. Null = saas.workspaces from config/landing-zone.yaml, else []."
  type        = list(string)
  default     = null

  validation {
    condition     = alltrue([for n in(var.saas_workspaces != null ? var.saas_workspaces : coalesce(local.cfg.saas_workspaces, [])) : can(regex("^[a-z0-9][a-z0-9-]*$", n))])
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

variable "disable_speculative_on_production" {
  description = "Disable automatic speculative PR plans on production workload workspaces (gcp-workload-<env> / aws-workload-<env> whose environment is_production, or whose key is prod / production when is_production is unset). A speculative plan runs the PR's code with the workspace's plan identity, so on a production workspace any PR author could read production through it. Default true; non-production workloads keep speculative plans."
  type        = bool
  default     = true
}

variable "enable_health_assessments" {
  description = "Enable TFC health assessments (native drift detection + continuous validation) on every managed workspace. Requires a PAID HCP Terraform tier that includes them (set false on the free tier)."
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
  description = "Group workspaces into one TFC project per cloud (<prefix>gcp, <prefix>aws, <prefix>saas, <prefix>platform; plus <prefix>gcp-workloads / <prefix>aws-workloads when split_workload_projects). Default true. Required for team access."
  type        = bool
  default     = true
}

variable "project_name_prefix" {
  description = "Prefix for TFC project (<prefix><cloud>), variable-set and policy-set names. Null = org.tfc.project_name_prefix from config/landing-zone.yaml, else \"landing-zone-\". An explicit org.tfc.<cloud>_project in the config overrides one project's name; aws-organization derives its OIDC-trust tfc_project from the same keys."
  type        = string
  default     = null
}

variable "platform_team_id" {
  description = "TFC team ID (team-...) of the broad platform team: fixed WRITE on workload workspaces (saas, gcp/aws workloads), and only custom plan-level access on control-plane workspaces (see platform_team_control_plane_runs and control_plane_approvers_team_id). Null = no grant."
  type        = string
  default     = null

  validation {
    condition     = var.platform_team_id == null || can(regex("^team-[A-Za-z0-9]+$", var.platform_team_id))
    error_message = "platform_team_id must be a TFC team ID (team-...)."
  }
}

variable "control_plane_approvers_team_id" {
  description = "TFC team ID (team-...) of the small control-plane approvers team: custom access on every project holding control-plane workspaces with runs = apply (confirm/discard applies) and variables/state read-only. It is the only team this root lets apply the control plane, so a platform-team member who edits code cannot also approve the apply. Must differ from platform_team_id. Null = no approvers grant (only organization owners can apply the control plane)."
  type        = string
  default     = null

  validation {
    condition     = var.control_plane_approvers_team_id == null || can(regex("^team-[A-Za-z0-9]+$", var.control_plane_approvers_team_id))
    error_message = "control_plane_approvers_team_id must be a TFC team ID (team-...)."
  }
}

variable "platform_team_control_plane_runs" {
  description = "Runs permission of platform_team_id on projects holding control-plane workspaces (custom access; variables read-only, no locking, workspace create/delete/move, run tasks or policy overrides). plan (default) = queue plans only, applies are confirmed by control_plane_approvers_team_id; read = view runs only; apply = may also confirm applies (variables stay read-only). Workload workspaces keep fixed write access."
  type        = string
  default     = "plan"

  validation {
    condition     = contains(["read", "plan", "apply"], var.platform_team_control_plane_runs)
    error_message = "platform_team_control_plane_runs must be read, plan or apply."
  }
}

variable "split_workload_projects" {
  description = "Place gcp-workload-<env> / aws-workload-<env> workspaces in separate <prefix>gcp-workloads / <prefix>aws-workloads TFC projects (names overridable via org.tfc.gcp_workloads_project / org.tfc.aws_workloads_project), so control-plane and workload access are granted per project. Null = org.tfc.split_workload_projects from config/landing-zone.yaml, else false (one project per cloud; control-plane hardening then uses workspace-level grants). With AWS, the workload accounts' OIDC trust must name the workloads project (aws-organization tfc_workspace_bindings[*].project) before enabling this."
  type        = bool
  default     = null
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
  description = "Create an OPA policy set sourced from policies/opa in the VCS repo, attached to every managed workspace. Enforcement is mixed: 7 mandatory + 3 advisory policies (policies/opa/policies.hcl); mandatory failures are not overridable unless policy_set_overridable = true. Requires vcs_repo and a PAID HCP Terraform tier with policy enforcement. Default false."
  type        = bool
  default     = false
}

variable "policy_set_overridable" {
  description = "Whether a failed MANDATORY policy in the OPA set can be overridden by a user with Manage Policy Overrides. Default false: mandatory policies are hard gates (advisory policies never block anyway). Set true only as a documented, time-boxed break-glass."
  type        = bool
  default     = false
}

variable "opa_version" {
  description = "OPA version for the policy set, pinned so a TFC default bump cannot change policy evaluation unreviewed. Keep it equal to the OPA_VERSION the CI policy tests use (.github/workflows/terraform-plan.yml) and to a version HCP Terraform offers. Null = the TFC default (latest)."
  type        = string
  default     = "1.22.2"

  validation {
    condition     = var.opa_version == null || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", coalesce(var.opa_version, "0.0.0")))
    error_message = "opa_version must be an exact semantic version such as 1.22.2 (or null for the TFC default)."
  }
}

variable "terraform_version" {
  description = "Terraform version constraint applied to every managed workspace, e.g. ~> 1.9. Null uses the TFC default."
  type        = string
  default     = "~> 1.9"
}

variable "vcs_repo" {
  description = "Optional VCS connection applied to every workspace (and the OPA policy set): {identifier = \"org/repo\", branch = \"main\", oauth_token_id = \"ot-...\"} or github_app_installation_id. Null = org.tfc.vcs_repo from config/landing-zone.yaml, else API/CLI-driven workspaces."
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
