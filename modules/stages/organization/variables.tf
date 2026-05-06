variable "domain" {
  description = "The primary domain of the GCP organization (e.g., example.com)"
  type        = string
}

variable "org_id" {
  description = "The numeric GCP organization ID"
  type        = string
}

variable "admin_project_id" {
  description = "The project ID of the bootstrap admin project"
  type        = string
}

variable "admin_project_number" {
  description = "The project number of the bootstrap admin project"
  type        = string
}

variable "customer_id" {
  description = "The Google Workspace customer ID (format: C followed by alphanumerics)"
  type        = string
}

variable "admin_email" {
  description = "Email address of the primary administrator"
  type        = string
}

variable "break_glass_user" {
  description = "Optional email address of a break-glass emergency user granted org admin access"
  type        = string
  default     = null
}

variable "terraform_admin_email" {
  description = "Email address of the Terraform admin service account"
  type        = string
}

variable "billing_account" {
  description = "The GCP billing account ID"
  type        = string
}

variable "project_prefix" {
  description = "Short prefix applied to all project IDs to ensure global uniqueness"
  type        = string
}

variable "environments" {
  description = "Map of environment definitions keyed by environment name (e.g., dev, staging, prod)"
  type = map(object({
    display_name            = string
    description             = string
    iam_group_role_bindings = map(set(string))
  }))

  validation {
    condition     = length(var.environments) > 0
    error_message = "At least one environment must be defined."
  }
}

variable "organization_admin_groups" {
  description = "List of Google Groups to grant organization admin roles"
  type        = list(string)
}

variable "billing_admin_groups" {
  description = "List of Google Groups to grant billing admin roles"
  type        = list(string)
}

variable "default_region" {
  description = "Default GCP region for regional resources"
  type        = string
}

variable "allowed_regions" {
  description = "List of GCP regions permitted by resource location org policy"
  type        = list(string)

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "allowed_regions must contain at least one region."
  }
}

variable "strict_folder_policy_environment_keys" {
  description = "Subset of environment keys that enforce strict resource location policies"
  type        = list(string)
}

variable "security_contact_email" {
  description = "Email address for security notifications (SCC, alerts)"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.security_contact_email))
    error_message = "security_contact_email must be a valid email address."
  }
}

variable "billing_contact_email" {
  description = "Email address for billing notifications and budget alerts"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.billing_contact_email))
    error_message = "billing_contact_email must be a valid email address."
  }
}

variable "monthly_budget_amount" {
  description = "Monthly budget cap in the configured currency. Must be greater than zero."
  type        = number

  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "monthly_budget_amount must be greater than zero."
  }
}

variable "budget_currency" {
  description = "ISO 4217 currency code for the budget (e.g., USD, EUR, GBP)"
  type        = string

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.budget_currency))
    error_message = "budget_currency must be a 3-letter ISO 4217 currency code (e.g., USD, EUR)."
  }
}
