variable "customer_id" {
  description = "The customer ID of the Google Cloud organization (e.g., 'C0abc123')"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]+$", var.customer_id))
    error_message = "Customer ID must be alphanumeric (e.g., 'C0abc123')."
  }
}

variable "identity_groups" {
  description = "List of identity groups to create"
  type = list(object({
    id                   = string
    display_name         = string
    email                = string
    description          = optional(string)
    initial_group_config = optional(string, "WITH_INITIAL_OWNER")
    labels               = optional(map(string), {})
  }))
  default = []

  validation {
    condition     = alltrue([for g in var.identity_groups : can(regex("^[^@]+@[^@]+\\.[^@]+$", g.email))])
    error_message = "Each identity group email must be a valid email address (e.g., 'group@example.com')."
  }
}
