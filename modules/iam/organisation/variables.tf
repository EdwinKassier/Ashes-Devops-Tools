variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com')"
  type        = string
}

variable "project_id" {
  description = "The project ID to enable services in"
  type        = string
}

variable "org_admin_members" {
  description = "List of members to have organization admin role"
  type        = list(string)
  default     = []
}

variable "billing_admin_members" {
  description = "List of members to have billing admin role"
  type        = list(string)
  default     = []
}

variable "allowed_regions" {
  description = "List of allowed GCP regions for resource creation"
  type        = list(string)
  default     = ["europe-west1", "europe-west2", "us-central1"]  # Example defaults
}


variable "customer_id" {
  description = "The customer ID of the Google Cloud organization (e.g., 'A01b123xz')"
  type        = string
}


# Organizational Units Configuration
variable "organizational_units" {
  description = "Map of organizational units to create"
  type = map(object({
    display_name = string
    description  = optional(string, "")
    projects = optional(map(object({
      name            = string
      billing_account = string
      folder_id       = optional(string)
      labels          = optional(map(string), {})
    })), {})
  }))
  default = {
    development = {
      display_name = "Development"
      description  = "Development environment"
    },
    uat = {
      display_name = "UAT"
      description  = "User Acceptance Testing environment"
    },
    production = {
      display_name = "Production"
      description  = "Production environment"
    }
  }
}

variable "project_labels" {
  description = "Common labels to apply to all projects"
  type        = map(string)
  default     = {}
}

variable "admin_email" {
  description = "Email address for the organization administrator"
  type        = string
}

variable "developers_group_email" {
  description = "Email address for the developers group"
  type        = string
}