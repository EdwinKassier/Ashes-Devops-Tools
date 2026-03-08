variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com')"
  type        = string
}

variable "project_id" {
  description = "The project ID to enable services in"
  type        = string
}

variable "org_admin_members" {
  description = "List of members to have organization admin role (format: user:email, group:email, serviceAccount:email, or domain:domain)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for m in var.org_admin_members :
      can(regex("^(user:|group:|serviceAccount:|domain:)", m))
    ])
    error_message = "Each member must be prefixed with 'user:', 'group:', 'serviceAccount:', or 'domain:'."
  }
}

variable "billing_admin_members" {
  description = "List of members to have billing admin role (format: user:email, group:email, serviceAccount:email, or domain:domain)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for m in var.billing_admin_members :
      can(regex("^(user:|group:|serviceAccount:|domain:)", m))
    ])
    error_message = "Each member must be prefixed with 'user:', 'group:', 'serviceAccount:', or 'domain:'."
  }
}




variable "customer_id" {
  description = "The customer ID of the Google Cloud organization (e.g., 'C0abc123')"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]+$", var.customer_id))
    error_message = "Customer ID must be alphanumeric (e.g., 'C0abc123')."
  }
}


# Organizational Units Configuration
# Organizational Units Configuration
variable "organizational_units" {
  description = "Map of organizational units to create"
  type = map(object({
    display_name            = string
    description             = optional(string, "")
    iam_group_role_bindings = optional(map(set(string)), {})
  }))
  default = {}
}

variable "group_defaults" {
  description = "Deprecated. Group membership is no longer managed by this module."
  type        = map(list(string))
  default     = {}
}
