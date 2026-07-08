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

# Organizational Units Configuration
variable "organizational_units" {
  description = "Map of organizational units to create"
  type = map(object({
    display_name            = string
    iam_group_role_bindings = optional(map(set(string)), {})
  }))
  default = {}
}

