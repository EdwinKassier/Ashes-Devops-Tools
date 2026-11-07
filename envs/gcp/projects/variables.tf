variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
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
  description = "Map of application environment definitions. is_production (default false) is surfaced as environment_config[<env>].is_production for the gcp-workload guardrail checks. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin)."
  type = map(object({
    display_name            = string
    region                  = string
    cidr_block              = string
    budget_monthly_limit    = number
    iam_group_role_bindings = map(set(string))
    labels                  = optional(map(string), {})
    is_production           = optional(bool, false)
  }))
  default = null

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
  })
  default = null

  validation {
    condition     = var.bootstrap_contract == null || alltrue([for k in ["suffix"] : try(length(trimspace(var.bootstrap_contract[k])) > 0, false)])
    error_message = "bootstrap_contract must set suffix for this root."
  }
}

variable "organization_contract" {
  description = "gcp-organization stage contract, the same type in every gcp root: org_id (numeric), billing_account (billingAccounts/XXXXXX-XXXXXX-XXXXXX or bare ID), admin_project_number, folders (key => {id, name, display_name}), tag_values (key => tag value ID) and scoped_access_policy_ids (env => policy ID). This root needs: billing_account, folders, tag_values (environment-<env>). Null = gcp.contracts.organization from config/landing-zone.yaml, else the contract output of the gcp-organization workspace."
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
