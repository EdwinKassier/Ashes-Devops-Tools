variable "org_id" {
  description = "The numeric Organization ID where tags will be defined (digits only, without 'organizations/' prefix)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be a numeric organization ID (digits only, without 'organizations/' prefix)."
  }
}

variable "tags" {
  description = <<-EOT
    Map of Tag Keys to their configuration. Each entry creates one Tag Key and its
    allowed Tag Values under the organization.

    Keys and value short_names follow GCP tag constraints: 1–63 characters, must
    start with a lowercase letter, may contain lowercase letters, digits, hyphens,
    and underscores. No spaces or uppercase.

    The optional `description` field sets a human-readable description on both the
    Tag Key resource and each of its Tag Values. Defaults to "Managed by Terraform"
    when omitted.

    Example:
      tags = {
        "environment" = {
          values      = ["dev", "staging", "prod"]
          description = "Deployment environment tier"
        }
        "cost-center" = {
          values = ["engineering", "marketing"]
        }
      }
  EOT
  type = map(object({
    values      = list(string)
    description = optional(string, "Managed by Terraform")
  }))

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
      for key, cfg in var.tags : [
        for v in cfg.values : can(regex("^[a-z][a-z0-9_-]{0,62}$", v))
      ]
    ]))
    error_message = "Tag values must start with a lowercase letter and contain only lowercase letters, digits, hyphens, and underscores (max 63 characters)."
  }
}
