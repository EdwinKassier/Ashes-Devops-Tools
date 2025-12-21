variable "customer_id" {
  description = "The customer ID of the Google Cloud organization (e.g., 'A01b123xz')"
  type        = string
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
}
