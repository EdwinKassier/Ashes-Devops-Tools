variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com')"
  type        = string
}

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

variable "organization_name" {
  description = "Name of the organization"
  type        = string
  default     = "My Organization"
}

# customer_id is now fetched dynamically via data.google_organization

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

variable "tfc_organization" {
  description = "Terraform Cloud organization used for dynamic credentials"
  type        = string
  default     = null
}

variable "shared_iam_group_role_bindings" {
  description = "Folder IAM bindings for the shared services folder, keyed by Google Group email"
  type        = map(set(string))
  default     = {}
}

variable "environments" {
  description = "Map of application environment definitions"
  type = map(object({
    display_name            = string
    region                  = string
    cidr_block              = string
    budget_monthly_limit    = number
    iam_group_role_bindings = map(set(string))
    labels                  = optional(map(string), {})
  }))
}

variable "default_region" {
  description = "Default region for resources"
  type        = string
  default     = "europe-west1"
}

variable "hub_vpc_cidr_block" {
  description = "CIDR block for the hub network VPC. Must not overlap with DNS hub or spoke CIDRs."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.hub_vpc_cidr_block))
    error_message = "hub_vpc_cidr_block must be a valid CIDR notation (e.g. \"10.0.0.0/16\")."
  }
}

variable "dns_hub_vpc_cidr_block" {
  description = "CIDR block for the DNS hub VPC. Must not overlap with hub_vpc_cidr_block or spoke CIDRs."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.dns_hub_vpc_cidr_block))
    error_message = "dns_hub_vpc_cidr_block must be a valid CIDR notation (e.g. \"10.1.0.0/16\")."
  }
}

variable "allowed_regions" {
  description = "List of allowed GCP regions for resource creation"
  type        = list(string)
  default     = ["europe-west1", "europe-west2", "us-central1"]
}

variable "strict_folder_policy_environment_keys" {
  description = "Environment folder keys that should receive the stricter folder policy bundle"
  type        = list(string)
  default     = ["prod"]
}

variable "admin_email" {
  description = "Email address for the organization administrator"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.admin_email))
    error_message = "admin_email must be a valid email address."
  }
}

variable "break_glass_user" {
  description = "Email address for the break glass user (optional). Grants Organization Admin."
  type        = string
  default     = null

  validation {
    condition     = var.break_glass_user == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.break_glass_user))
    error_message = "break_glass_user must be a valid email address when provided."
  }
}

variable "organization_admin_groups" {
  description = "List of groups to be granted Organization Admin role"
  type        = list(string)
  default     = []
}

variable "billing_admin_groups" {
  description = "List of groups to be granted Billing Admin role"
  type        = list(string)
  default     = []
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

variable "github_org" {
  description = "GitHub organization name for WIF OIDC trust condition. Must be set explicitly — no default to prevent accidentally trusting the wrong org when forking."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix) for WIF OIDC trust condition. Must be set explicitly — no default to prevent accidentally trusting the wrong repo when forking."
  type        = string
}

variable "security_contact_email" {
  description = "Email for security notifications via Essential Contacts (optional)"
  type        = string
  default     = null
}

variable "billing_contact_email" {
  description = "Email for billing notifications via Essential Contacts (optional)"
  type        = string
  default     = null
}

variable "monthly_budget_amount" {
  description = "Monthly budget limit for the organization. Set to 0 to disable budget alerts."
  type        = number
  default     = 1000
}

variable "budget_currency" {
  description = "ISO 4217 currency code for budget alerts (e.g., USD, EUR, GBP)"
  type        = string
  default     = "USD"

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.budget_currency))
    error_message = "budget_currency must be a 3-letter ISO 4217 currency code (e.g., USD, EUR)."
  }
}

variable "vpc_sc_access_policy_name" {
  description = <<-EOT
    Bare numeric ID of the existing organisation-level Access Context Manager access policy
    used by the hub VPC-SC perimeter (e.g. '1234567890').
    Do NOT include the 'accessPolicies/' prefix.
    Optional — if null, no VPC-SC perimeter is created for the hub network.
    Find your policy ID: gcloud access-context-manager policies list --organization=ORG_ID
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.vpc_sc_access_policy_name == null || can(regex("^[0-9]+$", var.vpc_sc_access_policy_name))
    error_message = "vpc_sc_access_policy_name must be a bare numeric ID (e.g. '1234567890'). Do not include the 'accessPolicies/' prefix."
  }
}

variable "vpc_sc_enable_dry_run" {
  description = <<-EOT
    When true, the hub VPC-SC perimeter logs violations but does NOT block traffic (dry-run/simulation mode).
    When false (the default), the perimeter is ENFORCED.
    Only set to true temporarily during the enforcement transition validation window.
  EOT
  type        = bool
  default     = false
}

variable "enable_tfc_oidc" {
  description = "Whether to provision Workload Identity Federation pools for Terraform Cloud OIDC. Set to false if using a different CI/CD system."
  type        = bool
  default     = true
}

variable "terraform_admin_email" {
  description = <<-EOT
    Service account email for the Terraform admin SA created by the bootstrap stage.
    The organization providers impersonate this SA for all API calls, ensuring that
    even local runs operate with the SA's permissions rather than the caller's personal
    credentials.
    Format: terraform@<admin-project-id>.iam.gserviceaccount.com
    Set to null only during the very first bootstrap apply when the SA does not exist yet.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.terraform_admin_email == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a GCP service account email (ends in .iam.gserviceaccount.com) or null."
  }
}
