variable "project_prefix" {
  description = <<-EOT
    Short prefix prepended to all project names created by this bootstrap.
    Constraints: 1–10 characters, starts with a lowercase letter, may contain
    lowercase letters, digits, and hyphens. Kept short so the full project ID
    stays within GCP's 30-character limit after suffixes are appended.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and be at most 10 characters long."
  }
}

variable "org_id" {
  description = "Numeric GCP Organization ID (digits only, without the 'organizations/' prefix)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be a numeric organization ID (digits only, without 'organizations/' prefix)."
  }
}

variable "billing_account" {
  description = "Billing Account ID in format XXXXXX-XXXXXX-XXXXXX"
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account))
    error_message = "billing_account must be a valid GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX (uppercase alphanumeric groups separated by hyphens)."
  }
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
  description = "GitHub organization name. No defaults — must be set explicitly to avoid accidentally trusting the wrong org when forking."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.github_org))
    error_message = "github_org must contain only alphanumeric characters and hyphens, starting with an alphanumeric character."
  }
}

variable "github_repo" {
  description = "GitHub repository name (without owner prefix). No defaults — must be set explicitly to avoid accidentally trusting the wrong repo when forking."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*$", var.github_repo))
    error_message = "github_repo must contain only alphanumeric characters, hyphens, underscores, and dots, starting with an alphanumeric character."
  }
}

# Terraform Cloud Configuration
variable "enable_tfc_oidc" {
  description = "Enable Terraform Cloud OIDC for Dynamic Credentials"
  type        = bool
  default     = true
}

variable "tfc_organization" {
  description = "Terraform Cloud organization name. Required (non-null) when enable_tfc_oidc = true — leaving it null while enable_tfc_oidc = true silently skips pool creation with no error."
  type        = string
  default     = null

  validation {
    condition     = var.tfc_organization == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.tfc_organization))
    error_message = "tfc_organization must contain only alphanumeric characters and hyphens."
  }

  validation {
    condition     = !var.enable_tfc_oidc || var.tfc_organization != null
    error_message = "tfc_organization must be set (non-null) when enable_tfc_oidc = true. The TFC OIDC pool is silently skipped when tfc_organization is null."
  }
}

variable "tfc_workspaces" {
  description = "List of TFC workspaces to grant access to Terraform Admin SA. Must be non-empty when enable_tfc_oidc = true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_tfc_oidc || length(var.tfc_workspaces) > 0
    error_message = "tfc_workspaces must contain at least one workspace name when enable_tfc_oidc = true."
  }
}
