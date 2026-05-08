variable "domain" {
  description = "The primary domain of the GCP organization (e.g., 'example.com')"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]*\\.[a-zA-Z]{2,}$", var.domain))
    error_message = "domain must be a valid domain name (e.g., 'example.com')."
  }
}

variable "org_id" {
  description = "The numeric GCP organization ID (digits only, no 'organizations/' prefix)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must contain only digits (e.g., '123456789012'). Do not include the 'organizations/' prefix."
  }
}

variable "admin_project_id" {
  description = "The project ID of the bootstrap admin project"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.admin_project_id))
    error_message = "admin_project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "admin_project_number" {
  description = "The numeric project number of the bootstrap admin project (digits only)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.admin_project_number))
    error_message = "admin_project_number must contain only digits."
  }
}

variable "customer_id" {
  description = "The Google Workspace customer ID (format: 'C' followed by alphanumerics, e.g., 'C0abc1234')"
  type        = string

  validation {
    condition     = can(regex("^C[0-9a-z]+$", var.customer_id))
    error_message = "customer_id must start with 'C' followed by alphanumeric characters (e.g., 'C0abc1234')."
  }
}

variable "admin_email" {
  description = "Email address of the primary administrator"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.admin_email))
    error_message = "admin_email must be a valid email address."
  }
}

variable "break_glass_user" {
  description = "Optional email address of a break-glass emergency user granted org admin access"
  type        = string
  default     = null

  validation {
    condition     = var.break_glass_user == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.break_glass_user))
    error_message = "break_glass_user must be null or a valid email address."
  }
}

variable "terraform_admin_email" {
  description = "Email address of the Terraform admin service account"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a valid email address."
  }
}

variable "billing_account" {
  description = "The GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX"
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account))
    error_message = "billing_account must be a valid GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "project_prefix" {
  description = "Short prefix applied to all project IDs to ensure global uniqueness (lowercase letters, digits, hyphens; starts with letter)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
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
  description = "List of Google Group email addresses to grant organization admin roles"
  type        = list(string)

  validation {
    condition     = alltrue([for g in var.organization_admin_groups : can(regex("^[^@]+@[^@]+\\.[^@]+$", g))])
    error_message = "Each organization_admin_groups entry must be a valid email address."
  }
}

variable "billing_admin_groups" {
  description = "List of Google Group email addresses to grant billing admin roles"
  type        = list(string)

  validation {
    condition     = alltrue([for g in var.billing_admin_groups : can(regex("^[^@]+@[^@]+\\.[^@]+$", g))])
    error_message = "Each billing_admin_groups entry must be a valid email address."
  }
}

variable "default_region" {
  description = "Default GCP region for regional resources (e.g., 'us-central1', 'europe-west1')"
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.default_region))
    error_message = "default_region must be a valid GCP region name (e.g., 'us-central1', 'europe-west1')."
  }
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
  description = "Email address for security notifications via Essential Contacts (SCC alerts, compliance notifications). Optional — if null, no Essential Contact is registered for the SECURITY category."
  type        = string
  default     = null

  validation {
    condition     = var.security_contact_email == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.security_contact_email))
    error_message = "security_contact_email must be a valid email address when provided."
  }
}

variable "billing_contact_email" {
  description = "Email address for billing notifications and budget alerts via Essential Contacts. Optional — if null, no Essential Contact is registered for the BILLING category."
  type        = string
  default     = null

  validation {
    condition     = var.billing_contact_email == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.billing_contact_email))
    error_message = "billing_contact_email must be a valid email address when provided."
  }
}

variable "monthly_budget_amount" {
  description = "Monthly budget cap in the configured currency. Set to 0 to disable budget alerts (no Budget resource will be created). Must be >= 0."
  type        = number

  validation {
    condition     = var.monthly_budget_amount >= 0
    error_message = "monthly_budget_amount must be 0 (disabled) or a positive number."
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

variable "audit_log_retention_days" {
  description = <<-EOT
    Number of days to retain audit logs in Cloud Storage. Adjust to meet your
    compliance requirements:
      - Default (365 days) — sufficient for most cloud security baselines.
      - PCI-DSS requires 12 months online + 12 months archival.
      - HIPAA requires 6 years.
      - FedRAMP requires 3 years.
    Must be >= 1.
  EOT
  type        = number
  default     = 365

  validation {
    condition     = var.audit_log_retention_days >= 1
    error_message = "audit_log_retention_days must be at least 1."
  }
}
