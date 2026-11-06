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

# ─── Automation identities ────────────────────────────────────────

variable "workload_service_accounts" {
  description = "Map of environment key -> { plan, apply } SA emails (gcp-bootstrap output workload_service_accounts). Each pair is granted var.workload_folder_roles on its OWN environment folder (var.folders[<env>]). Default {} = no grants."
  type = map(object({
    plan  = string
    apply = string
  }))
  default = {}

  validation {
    condition     = alltrue([for env, sas in var.workload_service_accounts : can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", sas.plan)) && can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", sas.apply)) && sas.plan != sas.apply])
    error_message = "Each workload_service_accounts entry needs distinct plan and apply service-account emails (*.iam.gserviceaccount.com)."
  }

  validation {
    condition     = alltrue([for env in keys(var.workload_service_accounts) : contains(keys(var.folders), env)])
    error_message = "Every workload_service_accounts key must be an environment present in var.folders (grants are scoped to that environment's folder)."
  }
}

variable "workload_folder_roles" {
  description = "Roles granted to each workload SA on its environment folder ({ plan, apply }). Must match the gcp-bootstrap delegation allow-list (read it from the gcp-bootstrap output workload_folder_roles)."
  type = object({
    plan  = list(string)
    apply = list(string)
  })
  default = {
    plan  = []
    apply = []
  }

  validation {
    condition     = !contains(concat(var.workload_folder_roles.plan, var.workload_folder_roles.apply), "roles/owner")
    error_message = "roles/owner must not be granted to workload SAs."
  }
}

variable "network_service_accounts" {
  description = "The network-hub stage { plan, apply } SA emails (gcp-bootstrap output stage_service_accounts[\"network-hub\"]). Granted var.network_folder_roles on the var.network_folder_key folder. Null = no grants."
  type = object({
    plan  = string
    apply = string
  })
  default = null

  validation {
    condition     = var.network_service_accounts == null || contains(keys(var.folders), var.network_folder_key)
    error_message = "network_service_accounts is set but var.folders has no network_folder_key entry (default \"shared\") to scope the grants to."
  }
}

variable "network_folder_roles" {
  description = "Roles granted to the network-hub SAs on the shared/network folder ({ plan, apply }); read from the gcp-bootstrap output network_folder_roles."
  type = object({
    plan  = list(string)
    apply = list(string)
  })
  default = {
    plan  = []
    apply = []
  }
}

variable "network_folder_key" {
  description = "Key in var.folders of the folder holding the hub/DNS projects (network-hub SAs are granted roles there)."
  type        = string
  default     = "shared"
}
