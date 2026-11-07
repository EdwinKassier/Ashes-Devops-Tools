variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com'). Null = org.domain from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(coalesce(var.domain, local.cfg.domain, " "))) > 0
    error_message = "domain is unset: set var.domain or org.domain in config/landing-zone.yaml."
  }
}

variable "project_prefix" {
  description = <<-EOT
    Short prefix prepended to all GCP project IDs to ensure global uniqueness.
    Must start with a lowercase letter; only lowercase letters, digits, and hyphens allowed.
    Keep this to 6 characters or fewer — GCP project IDs are capped at 30 characters and
    the prefix consumes part of that budget. Null = org.prefix from
    config/landing-zone.yaml (shared by every GCP root). The placeholder "my-org" is rejected.
  EOT
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

# customer_id is now fetched dynamically via data.google_organization

variable "billing_account" {
  description = "Billing account ID (optional if billing_account_display_name is provided). Null = gcp.billing_account from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = coalesce(var.billing_account, local.cfg.billing_account, var.billing_account_display_name, "!unset") != "!unset"
    error_message = "At least one of billing_account (or gcp.billing_account in config/landing-zone.yaml) or billing_account_display_name must be set."
  }

  validation {
    condition     = !startswith(coalesce(var.billing_account, local.cfg.billing_account, "ok"), "REPLACE_WITH")
    error_message = "billing_account is still the config/landing-zone.example.yaml placeholder: set your billing account ID."
  }
}

variable "billing_account_display_name" {
  description = "Display name of the billing account (used if billing_account ID is not provided)"
  type        = string
  default     = null
}

variable "tfc_organization" {
  description = "Terraform Cloud organization used for dynamic credentials. Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null
}

variable "shared_iam_group_role_bindings" {
  description = "Folder IAM bindings for the shared services folder, keyed by Google Group email"
  type        = map(set(string))
  default     = {}
}

variable "environments" {
  description = "Map of application environment definitions. is_production (default false) marks production environments: it drives the production guardrail checks here and in gcp-bootstrap / gcp-workload. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin)."
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

variable "gcp_overrides" {
  description = "Explicit overrides of the gcp section (config/landing-zone.yaml gcp.*) fed to the organization stage. Every key is optional and the type is the stage's gcp object: a set (non-null) key wins over the config file, an unset or null key keeps the config value, else the stage default. Keys that are not in the config schema (enable_pam, logging_project_id, ...) are set only here. Precedence: gcp_overrides > config/landing-zone.yaml > built-in default. See UPGRADING.md for the old variable names."
  type = object({
    admin_email                           = optional(string)
    break_glass_user                      = optional(string)
    organization_admin_groups             = optional(list(string))
    billing_admin_groups                  = optional(list(string))
    allow_user_principals_for_break_glass = optional(bool)
    allowed_regions                       = optional(list(string))
    strict_folder_policy_environment_keys = optional(list(string))
    enforce_os_login                      = optional(bool)
    os_login_exempt_environment_keys      = optional(list(string))
    security_contact_email                = optional(string)
    billing_contact_email                 = optional(string)
    budget_currency                       = optional(string)
    logging_project_id                    = optional(string)
    logging_project_number                = optional(string)
    audit_soft_delete_retention_days      = optional(number)
    enable_control_plane_alerting         = optional(bool)
    enable_cis_log_metrics                = optional(bool)
    alert_notification_emails             = optional(list(string))
    alert_notification_channels           = optional(list(string))
    break_glass_principal_emails          = optional(list(string))
    custom_org_constraints = optional(list(object({
      name           = string
      display_name   = string
      description    = string
      action_type    = string
      condition      = string
      method_types   = list(string)
      resource_types = list(string)
      enforcement    = optional(string, "enforce")
    })))
    enable_audit_bucket_lock = optional(bool)
    iam_deny_policies = optional(list(object({
      name         = string
      display_name = optional(string)
      rules = list(object({
        description           = optional(string)
        denied_principals     = list(string)
        denied_permissions    = list(string)
        exception_principals  = optional(list(string), [])
        exception_permissions = optional(list(string), [])
        denial_condition = optional(object({
          expression  = string
          title       = optional(string)
          description = optional(string)
        }))
      }))
    })))
    enable_cmek_org_policy                      = optional(bool)
    cmek_required_services                      = optional(list(string))
    enable_admin_containment                    = optional(bool)
    containment_exempt_principals               = optional(list(string))
    enable_legacy_admin_folder_roles            = optional(bool)
    enable_scoped_access_policies               = optional(bool)
    enable_pam                                  = optional(bool)
    pam_eligible_groups                         = optional(list(string))
    pam_approver_groups                         = optional(list(string))
    pam_max_request_duration                    = optional(string)
    guardrail_owner_mode                        = optional(string)
    prefer_managed_constraints                  = optional(bool)
    enable_log_analytics                        = optional(bool)
    log_analytics_retention_days                = optional(number)
    enable_logging_organization_settings        = optional(bool)
    logging_settings_kms_key_name               = optional(string)
    enable_principal_access_boundary            = optional(bool)
    principal_access_boundary_allowed_resources = optional(list(string))
    restrict_cloud_run_ingress                  = optional(bool)
    allowed_workload_identity_issuers           = optional(list(string))
    allowed_workload_identity_aws_accounts      = optional(list(string))
    org_policy_overrides = optional(map(object({
      enforce        = optional(bool)
      allowed_values = optional(list(string))
      denied_values  = optional(list(string))
      allow_all      = optional(bool)
      deny_all       = optional(bool)
      disabled       = optional(bool, false)
    })))
    wif_tenant_pin_enforcement = optional(string)
  })
  default  = {}
  nullable = false
}

# Stage contract override (FAST-style): when set (here or as gcp.contracts.bootstrap
# in config/landing-zone.yaml) the gcp-bootstrap remote-state read is skipped.
variable "bootstrap_contract" {
  description = "gcp-bootstrap stage contract, the same type in every gcp root: admin_project_id, admin_project_number, terraform_admin_email, suffix, plus the optional automation identities (workload_service_accounts, stage_service_accounts, workload/network_folder_roles, delegated_workload/network_folder_roles; omitted = no grants) and guardrail_owner_mode. This root needs: admin_project_id, admin_project_number, terraform_admin_email. Null = gcp.contracts.bootstrap from config/landing-zone.yaml, else the contract output of the gcp-bootstrap workspace."
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
    condition     = var.bootstrap_contract == null || can(regex("^[0-9]+$", var.bootstrap_contract.admin_project_number))
    error_message = "bootstrap_contract.admin_project_number must be numeric."
  }

  validation {
    condition     = var.bootstrap_contract == null || alltrue([for k in ["terraform_admin_email"] : try(length(trimspace(var.bootstrap_contract[k])) > 0, false)])
    error_message = "bootstrap_contract must set terraform_admin_email for this root."
  }
}

variable "bootstrap_workspace_name" {
  description = "Name of the gcp-bootstrap TFC workspace this root reads via remote state for the admin project, Terraform admin SA, and WIF pools."
  type        = string
  default     = "gcp-bootstrap"
}

variable "monthly_budget_amount" {
  description = "Monthly budget limit for the organization. Set to 0 to disable budget alerts (rejected for the starter profile). Null = org.monthly_budget_usd from config/landing-zone.yaml (starter profile only), else 1000 (production) / unset (starter, which then fails the plan)."
  type        = number
  default     = null

  validation {
    condition     = var.monthly_budget_amount == null || coalesce(var.monthly_budget_amount, 0) >= 0
    error_message = "monthly_budget_amount must be 0 (disabled) or a positive number."
  }
}

variable "profile" {
  description = "Cost/assurance profile: production (default) or starter. starter requires a monthly budget (monthly_budget_amount or org.monthly_budget_usd) and alerts at 50/80/100% of it. Null = org.profile from config/landing-zone.yaml, else production."
  type        = string
  default     = null

  validation {
    condition     = var.profile == null || contains(["production", "starter"], coalesce(var.profile, "production"))
    error_message = "profile must be production or starter."
  }
}

variable "terraform_admin_email" {
  description = <<-EOT
    Service account email for the Terraform admin SA created by the bootstrap stage.
    The organization providers impersonate this SA for all API calls, ensuring that
    even local runs operate with the SA's permissions rather than the caller's personal
    credentials.
    Format: terraform-admin@<admin-project-id>.iam.gserviceaccount.com
    Set to null only during the very first bootstrap apply when the SA does not exist yet.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.terraform_admin_email == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a GCP service account email (ends in .iam.gserviceaccount.com) or null."
  }
}

variable "tfc_hostname" {
  description = "HCP Terraform / Terraform Enterprise hostname whose dynamic-credential tokens the WIF pools trust (app.terraform.io, app.eu.terraform.io or your TFE host)."
  type        = string
  default     = "app.terraform.io"
}

variable "pin_wif_to_tfc_organization" {
  description = "Enforce (custom org-policy constraint) that every HCP Terraform workload identity provider references tfc_organization in its attribute_condition, so no pipeline can trust another TFC organization. Default true."
  type        = bool
  default     = true
}

variable "wif_github_owner_ids" {
  description = "Numeric GitHub owner IDs a GitHub Actions workload identity provider may pin: its attribute_condition must be exactly assertion.repository_owner_id == \"<id>\" for one of them. Empty (default) leaves GitHub providers tenant-unpinned (the issuer is still allow-listed)."
  type        = list(string)
  default     = []
  nullable    = false
}

