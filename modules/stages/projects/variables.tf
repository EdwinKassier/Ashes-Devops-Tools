variable "project_prefix" { type = string }
variable "organization_name" { type = string }
variable "default_billing_account" { type = string }
variable "admin_project_id" { type = string }
variable "folders" { type = map(any) }

variable "environments" {
  description = "Map of environment definitions"
  type = map(object({
    display_name = string
    description  = string
    groups = map(object({
      role = string
    }))
    projects = map(object({
      name            = string
      billing_account = optional(string)
      labels          = map(string)
    }))
  }))
}

variable "project_services" {
  type = list(string)
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
  description = "Random suffix from bootstrap module"
  type        = string
}
