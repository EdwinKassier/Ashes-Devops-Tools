variable "project_prefix" {
  description = "Short prefix applied to all project IDs for global uniqueness (e.g., 'my-org')"
  type        = string
}

variable "organization_name" {
  description = "Organization name applied as a label on all created projects"
  type        = string
}

variable "default_billing_account" {
  description = "Default GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX, used when a project does not specify its own billing account"
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.default_billing_account))
    error_message = "default_billing_account must be a valid GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX (uppercase alphanumeric groups separated by hyphens)."
  }
}

variable "admin_project_id" {
  description = "Project ID of the bootstrap admin project used as the metrics scope for monitoring"
  type        = string
}

variable "folders" {
  description = "Map of folder objects keyed by environment name, as output by the organization stage"
  type = map(object({
    id           = string
    name         = string
    display_name = string
  }))
}

variable "environments" {
  description = "Map of environment definitions keyed by environment name. Each environment must have at least one project."
  type = map(object({
    display_name = string
    description  = string
    projects = map(object({
      name            = string
      billing_account = optional(string)
      labels          = map(string)
    }))
  }))

  validation {
    condition     = length(var.environments) > 0
    error_message = "At least one environment must be defined."
  }
}

variable "project_services" {
  description = "List of GCP APIs to enable on every created project"
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

variable "suffix" {
  description = "Random suffix from bootstrap module appended to project IDs for uniqueness"
  type        = string
  validation {
    condition     = can(regex("^[a-f0-9]+$", var.suffix))
    error_message = "suffix must be a lowercase hexadecimal string (e.g., 'abc123')."
  }
}
