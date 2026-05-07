variable "org_id" {
  description = "The numeric Organization ID where tags will be defined (digits only, without 'organizations/' prefix)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be a numeric organization ID (digits only, without 'organizations/' prefix)."
  }
}

variable "tags" {
  description = "Map of Tag Keys to a list of allowed Tag Values. Keys and values follow GCP tag short_name constraints: 1-63 chars, must start with a lowercase letter, may contain lowercase letters, digits, hyphens, and underscores. No spaces or uppercase."
  type        = map(list(string))
  # Example:
  # {
  #   "environment" = ["dev", "prod", "uat"]
  #   "cost-center" = ["engineering", "marketing"]
  # }

  validation {
    condition     = length(var.tags) > 0
    error_message = "tags must contain at least one tag key."
  }

  validation {
    condition = alltrue([
      for key in keys(var.tags) :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", key))
    ])
    error_message = "Tag keys must start with a lowercase letter and contain only lowercase letters, digits, hyphens, and underscores (max 63 characters)."
  }

  validation {
    condition = alltrue(flatten([
      for key, values in var.tags : [
        for v in values : can(regex("^[a-z][a-z0-9_-]{0,62}$", v))
      ]
    ]))
    error_message = "Tag values must start with a lowercase letter and contain only lowercase letters, digits, hyphens, and underscores (max 63 characters)."
  }
}
