variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), relative to this root (a .yaml or .yml file inside the repository). Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. When set, the file must exist (the plan fails otherwise); the default path is read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null

  # SEC-1: only a relative .yaml/.yml path that stays inside the repository, so
  # the loader's file() cannot read a file on the runner (/proc/self/environ).
  validation {
    condition = var.landing_zone_config_path == null || var.landing_zone_config_path == "" || (
      can(regex("^[A-Za-z0-9_./-]+\\.ya?ml$", coalesce(var.landing_zone_config_path, "x"))) &&
      !startswith(coalesce(var.landing_zone_config_path, "x"), "/") &&
      length([for s in split("/", dirname("./${coalesce(var.landing_zone_config_path, "x")}/_")) : s if s == ".."]) <= 3
    )
    error_message = "landing_zone_config_path must be a relative path to a .yaml or .yml file inside the repository (no leading /, at most 3 leading ../ from this root): an absolute or escaping path could read a file on the runner."
  }

  # IAC-3: a path that is set must name a file, so a typo does not silently
  # drop the whole config and fall back to built-in defaults.
  validation {
    condition     = var.landing_zone_config_path == null || var.landing_zone_config_path == "" || startswith(coalesce(var.landing_zone_config_path, "/"), "/") || fileexists("${path.root}/${coalesce(var.landing_zone_config_path, "x")}")
    error_message = "landing_zone_config_path is set to \"${var.landing_zone_config_path == null ? "" : var.landing_zone_config_path}\" but no file exists there (relative to this root). Fix the path. In HCP Terraform only ../../../config/landing-zone.yaml or ../../../config/<estate>/landing-zone.yaml passes the policy check; \"\" disables the file in local and test runs only."
  }
}

variable "project_prefix" {
  description = "Short prefix prepended to all GCP project IDs. Null = org.prefix from config/landing-zone.yaml (shared by every GCP root)."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", coalesce(var.project_prefix, local.cfg.project_prefix, "!unset")))
    error_message = "project_prefix is unset or invalid: set var.project_prefix or org.prefix in config/landing-zone.yaml. It must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and be 10 characters or fewer."
  }

  validation {
    condition     = coalesce(var.project_prefix, local.cfg.project_prefix, "!unset") != "my-org"
    error_message = "project_prefix is still set to the placeholder 'my-org'. Set it to your organisation's actual identifier before deploying."
  }
}

variable "organization_name" {
  description = "Name of the organization. Null = org.display_name from config/landing-zone.yaml, else \"My Organization\"."
  type        = string
  default     = null
}

variable "enable_network_connectivity_center" {
  description = "Enable networkconnectivity.googleapis.com on the hub project and every environment host project, for the opt-in NCC hub/spoke connectivity. Null = true when config/landing-zone.yaml turns NCC on (gcp.network.ncc_hub.enabled, gcp.network.connectivity = ncc, or any gcp.environments.<env>.network_connectivity = ncc), else false."
  type        = bool
  default     = null
}

variable "project_services" {
  description = "List of APIs to enable on all projects"
  type        = list(string)
  default = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "cloudbilling.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

variable "environments" {
  description = "Map of application environment definitions. is_production (default false here; required on every gcp.environments entry in config/landing-zone.yaml) is surfaced as environment_config[<env>].is_production for the gcp-workload guardrail checks. data_classification (public, internal (default), confidential or restricted) binds the data-classification tag value of that name to the environment host project. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin)."
  type = map(object({
    display_name            = string
    region                  = string
    cidr_block              = string
    budget_monthly_limit    = number
    iam_group_role_bindings = map(set(string))
    labels                  = optional(map(string), {})
    is_production           = optional(bool, false)
    data_classification     = optional(string, "internal")
    compliance_class        = optional(string, "standard")
  }))
  default = null

  validation {
    # Review of the re-audit 6 fixes: an explicit environments map (a workspace
    # variable no review sees) must keep every regulated config environment,
    # still regulated, or the contract would publish it as standard.
    condition = var.environments == null || alltrue([
      for k, e in coalesce(local.cfg.environments, {}) :
      try(var.environments[k].compliance_class, "missing") == "regulated" if try(e.compliance_class, "standard") == "regulated"
    ])
    error_message = "environments must keep every environment that config/landing-zone.yaml marks regulated, with compliance_class = \"regulated\": ${join(", ", [for k, e in coalesce(local.cfg.environments, {}) : k if try(e.compliance_class, "standard") == "regulated" && try(var.environments[k].compliance_class, "missing") != "regulated"])}."
  }

  validation {
    condition     = var.environments != null || length(local.cfg.environments) > 0
    error_message = "environments is unset: define gcp.environments in config/landing-zone.yaml or set var.environments."
  }

  # Environment keys become project/workspace keys (e.g. "<env>-host",
  # "gcp-workload-<env>"). "shared" is reserved for the hub/DNS projects: a
  # right-wins merge() would silently replace them with an environment named
  # "shared". Keys must also be a valid lowercase token.
  validation {
    condition     = alltrue([for k in(var.environments != null ? keys(var.environments) : keys(local.cfg.environments)) : k != "shared" && can(regex("^[a-z][a-z0-9-]{0,14}$", k))])
    error_message = "environments keys must be lowercase tokens (^[a-z][a-z0-9-]{0,14}$) and must not be the reserved key \"shared\"."
  }

  validation {
    condition     = alltrue([for c in(var.environments != null ? [for e in values(var.environments) : e.cidr_block] : [for e in values(local.cfg.environments) : e.cidr_block]) : can(cidrnetmask(c))])
    error_message = "Each environment's cidr_block must be valid CIDR notation, e.g. 10.10.0.0/16."
  }

  validation {
    condition     = alltrue([for e in values(var.environments != null ? var.environments : local.cfg.environments) : contains(["public", "internal", "confidential", "restricted"], e.data_classification)])
    error_message = "Each environment's data_classification (gcp.environments.<env>.data_classification in config/landing-zone.yaml) must be public, internal, confidential or restricted."
  }

  validation {
    condition     = var.environments != null || length(local.cfg.environments_missing_is_production) == 0
    error_message = "Every gcp.environments entry in config/landing-zone.yaml must set is_production: true or false; the environment name is not read. Missing or invalid: ${join(", ", local.cfg.environments_missing_is_production)}."
  }
}

variable "default_region" {
  description = "Default region for resources. Null = org.regions.gcp from config/landing-zone.yaml, else europe-west2."
  type        = string
  default     = null
}

variable "terraform_admin_email" {
  description = "OPTIONAL SA for the providers to impersonate, for deliberate LOCAL human runs only. Leave null in Terraform Cloud: dynamic credentials already authenticate plan as <prefix>-projects-plan and apply as <prefix>-projects-apply."
  type        = string
  default     = null

  validation {
    condition     = var.terraform_admin_email == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a GCP service account email (ends in .iam.gserviceaccount.com) or null."
  }
}

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns the upstream workspaces read via remote state. Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null
}

variable "bootstrap_workspace_name" {
  description = "Name of the gcp-bootstrap TFC workspace (read via remote state for admin_project_id and suffix)."
  type        = string
  default     = "gcp-bootstrap"
}

variable "organization_workspace_name" {
  description = "Name of the gcp-organization TFC workspace (read via remote state for folders, tag values, and billing account)."
  type        = string
  default     = "gcp-organization"
}

# Stage contract overrides (FAST-style): when set (here or as gcp.contracts.<layer>
# in config/landing-zone.yaml) the matching remote-state read is skipped.
variable "bootstrap_contract" {
  description = "gcp-bootstrap stage contract, the same type in every gcp root: admin_project_id, admin_project_number, terraform_admin_email, suffix, plus the optional automation identities (workload_service_accounts, stage_service_accounts, workload/network_folder_roles, delegated_workload/network_folder_roles; omitted = no grants) and guardrail_owner_mode. This root needs: admin_project_id, suffix. Null = gcp.contracts.bootstrap from config/landing-zone.yaml, else the contract output of the gcp-bootstrap workspace."
  type = object({
    admin_project_id                = string
    admin_project_number            = optional(string)
    terraform_admin_email           = optional(string)
    suffix                          = optional(string)
    workload_service_accounts       = optional(map(object({ plan = string, apply = string })), {})
    stage_service_accounts          = optional(map(object({ plan = string, apply = string })), {})
    workload_folder_roles           = optional(object({ plan = list(string), apply = list(string) }), { plan = [], apply = [] })
    network_folder_roles            = optional(object({ plan = list(string), apply = list(string) }), { plan = [], apply = [] })
    delegated_workload_folder_roles = optional(list(string), [])
    delegated_network_folder_roles  = optional(list(string), [])
    guardrail_owner_mode            = optional(string, "separate")
    # gcp-organization's plan-time checks read these (omitted = null, no check).
    organization_apply_grantable_roles = optional(list(string))
    organization_admin_members         = optional(list(string))
  })
  default = null

  validation {
    condition     = var.bootstrap_contract == null || alltrue([for k in ["suffix"] : try(length(trimspace(var.bootstrap_contract[k])) > 0, false)])
    error_message = "bootstrap_contract must set suffix for this root."
  }
}

variable "organization_contract" {
  description = "gcp-organization stage contract, the same type in every gcp root: org_id (numeric), billing_account (the bare ID XXXXXX-XXXXXX-XXXXXX that gcp-organization emits, or billingAccounts/XXXXXX-XXXXXX-XXXXXX; the root strips the prefix), admin_project_number, folders (key => {id, name, display_name}), tag_values (key => tag value ID) and scoped_access_policy_ids (env => policy ID). This root needs: billing_account, folders, tag_values (environment-<env>). Null = gcp.contracts.organization from config/landing-zone.yaml, else the contract output of the gcp-organization workspace."
  type = object({
    org_id               = optional(string)
    billing_account      = optional(string)
    admin_project_number = optional(string)
    folders = optional(map(object({
      id           = string
      name         = string
      display_name = string
    })), {})
    tag_values               = optional(map(string), {})
    scoped_access_policy_ids = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.organization_contract == null || alltrue([for k in ["billing_account"] : try(length(trimspace(var.organization_contract[k])) > 0, false)])
    error_message = "organization_contract must set billing_account for this root."
  }
}
