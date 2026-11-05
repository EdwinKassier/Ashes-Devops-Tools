variable "project_prefix" {
  description = "Short prefix prepended to all GCP project IDs. Keep in sync with the gcp-organization root."
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
  description = "Map of application environment definitions. Keep in sync with the gcp-organization root."
  type = map(object({
    display_name            = string
    region                  = string
    cidr_block              = string
    budget_monthly_limit    = number
    iam_group_role_bindings = map(set(string))
    labels                  = optional(map(string), {})
  }))

  # Environment keys become project/workspace keys (e.g. "<env>-host",
  # "gcp-workload-<env>"). "shared" is reserved for the hub/DNS projects: a
  # right-wins merge() would silently replace them with an environment named
  # "shared". Keys must also be a valid lowercase token.
  validation {
    condition     = alltrue([for k in keys(var.environments) : k != "shared" && can(regex("^[a-z][a-z0-9-]{0,14}$", k))])
    error_message = "environments keys must be lowercase tokens (^[a-z][a-z0-9-]{0,14}$) and must not be the reserved key \"shared\"."
  }

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
  description = "OPTIONAL SA for the providers to impersonate, for deliberate LOCAL human runs only. Leave null in Terraform Cloud: dynamic credentials already authenticate plan as <prefix>-projects-plan and apply as <prefix>-projects-apply (audit C2)."
  type        = string
  default     = null

  validation {
    condition     = var.terraform_admin_email == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a GCP service account email (ends in .iam.gserviceaccount.com) or null."
  }
}

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns the upstream workspaces read via remote state."
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
