variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com')"
  type        = string
}

variable "project_prefix" {
  description = "Prefix to use for project names"
  type        = string
  default     = "my-org"
}

variable "organization_name" {
  description = "Name of the organization"
  type        = string
  default     = "My Organization"
}

# customer_id is now fetched dynamically via data.google_organization

variable "billing_account" {
  description = "Billing account ID (optional if display name provided)"
  type        = string
  default     = null
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
}

variable "break_glass_user" {
  description = "Email address for the break glass user (optional). Grants Organization Admin."
  type        = string
  default     = null
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
  description = "GitHub Organization for OIDC Federation"
  type        = string
  default     = "EdwinKassier"
}

variable "github_repo" {
  description = "GitHub Repository for OIDC Federation"
  type        = string
  default     = "Ashes-Devops-Tools"
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
  description = "Currency code for budget alerts (e.g., USD, EUR, GBP)"
  type        = string
  default     = "USD"
}
