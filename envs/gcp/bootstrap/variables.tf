variable "project_prefix" {
  description = <<-EOT
    Short prefix prepended to all GCP project IDs to ensure global uniqueness.
    Must start with a lowercase letter; only lowercase letters, digits, and hyphens allowed.
    Keep this to 6 characters or fewer — GCP project IDs are capped at 30 characters and
    the prefix consumes part of that budget.
    Set this to your organisation's identifier (e.g. "acme", "xyz-co"). Do NOT use the
    default value "my-org" in a real deployment.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and be 10 characters or fewer."
  }

  validation {
    condition     = var.project_prefix != "my-org"
    error_message = "project_prefix is still set to the placeholder 'my-org'. Set it to your organisation's actual identifier before deploying."
  }
}

variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com')"
  type        = string
}

variable "billing_account" {
  description = "Billing account ID (optional if billing_account_display_name is provided)"
  type        = string
  default     = null

  validation {
    condition     = var.billing_account != null || var.billing_account_display_name != null
    error_message = "At least one of billing_account or billing_account_display_name must be set."
  }
}

variable "billing_account_display_name" {
  description = "Display name of the billing account (used if billing_account ID is not provided)"
  type        = string
  default     = null
}

variable "admin_email" {
  description = "Email address for the organization administrator"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.admin_email))
    error_message = "admin_email must be a valid email address."
  }
}

variable "github_org" {
  description = "GitHub organization name for WIF OIDC trust condition. Must be set explicitly — no default to prevent accidentally trusting the wrong org when forking."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix) for WIF OIDC trust condition. Must be set explicitly — no default to prevent accidentally trusting the wrong repo when forking."
  type        = string
}

variable "tfc_organization" {
  description = "Terraform Cloud organization used for dynamic credentials"
  type        = string
  default     = null
}

variable "enable_tfc_oidc" {
  description = "Whether to provision Workload Identity Federation pools for Terraform Cloud OIDC. Set to false if using a different CI/CD system."
  type        = bool
  default     = true
}

variable "enable_privilege_split" {
  description = "Enable the bootstrap SA privilege split: route high-privilege org roles to a separate resman SA. Default false = unchanged. Enabling requires WIF binding + downstream impersonation switch. PREVIEW (not yet validated against a real apply)."
  type        = bool
  default     = false
}

variable "environments" {
  description = "Map of application environment definitions. Only the keys are used here (to derive the per-environment TFC workspace names that receive WIF trust); the full objects are consumed by the gcp-organization root."
  type = map(object({
    display_name            = string
    region                  = string
    cidr_block              = string
    budget_monthly_limit    = number
    iam_group_role_bindings = map(set(string))
    labels                  = optional(map(string), {})
  }))

  validation {
    condition     = alltrue([for e in values(var.environments) : can(cidrnetmask(e.cidr_block))])
    error_message = "Each environment's cidr_block must be valid CIDR notation, e.g. 10.10.0.0/16. Keep the environments map identical across the GCP roots."
  }
}

variable "default_region" {
  description = "Default region for resources"
  type        = string
  default     = "europe-west1"
}

variable "terraform_admin_email" {
  description = <<-EOT
    Service account email for the Terraform admin SA created by the bootstrap stage.
    The providers impersonate this SA for all API calls, ensuring that even local
    runs operate with the SA's permissions rather than the caller's personal
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
