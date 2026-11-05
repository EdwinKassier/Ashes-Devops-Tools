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

variable "bootstrap_workspace_name" {
  description = "Name of the gcp-bootstrap TFC workspace this root reads via remote state for the admin project, Terraform admin SA, and WIF pools."
  type        = string
  default     = "gcp-bootstrap"
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

variable "custom_org_constraints" {
  description = "Opt-in custom organization-policy constraints (CEL-defined resource-shape guardrails) applied at the org node. Default [] = none. Google recommends layering custom constraints on the managed baseline. See docs/known-gaps.md (G6)."
  type = list(object({
    name           = string
    display_name   = string
    description    = string
    action_type    = string
    condition      = string
    method_types   = list(string)
    resource_types = list(string)
  }))
  default = []
}

variable "enable_audit_bucket_lock" {
  description = "Opt-in WORM lock on the org audit-log GCS bucket (locked retention of audit_log_retention_days). Default false preserves the current operator-correctable behaviour. A locked policy is IRREVERSIBLE — enable only for compliance regimes that require tamper-proof retention. See docs/known-gaps.md (G8)."
  type        = bool
  default     = false
}

variable "iam_deny_policies" {
  description = "Opt-in IAM deny policies applied at the org node — a coarse, allow-independent backstop blocking specific permissions for specific principals regardless of roles (deny before allow). Default [] = none. See docs/known-gaps.md (G9)."
  type = list(object({
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
  }))
  default = []
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

# --- Audit finding G4: dedicated logging project (opt-in, default = unchanged) ---
variable "logging_project_id" {
  description = "Dedicated logging project ID for the org audit sink/bucket (separation of duties). Default null = admin project (unchanged). PREVIEW: opt-in (default off), not yet validated against a real apply.; ensure CMEK cross-project access."
  type        = string
  default     = null
}

variable "enable_cmek_org_policy" {
  description = "H1/M2: enforce CMEK on sensitive services org-wide (gcp.restrictNonCmekServices). Default false; set true (or use examples/presets/prod-gcp-organization.tfvars) once CMEK keys are wired for cmek_required_services."
  type        = bool
  default     = false
}

variable "cmek_required_services" {
  description = "Services that require CMEK when enable_cmek_org_policy is true."
  type        = list(string)
  default = [
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "sqladmin.googleapis.com",
    "spanner.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}
