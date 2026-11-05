/**
 * Copyright 2023 Ashes
 *
 * Secret Manager Module - Variables
 */

variable "project_id" {
  description = "The GCP project ID where the secrets are created."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "secrets" {
  description = <<-EOT
    Map of secret name => configuration. Each secret creates a container only; secret
    VALUES are not managed here by default (see var.secret_values).
      labels      = labels applied to the secret
      replication = { automatic = bool, user_managed_regions = list(string) }
                    When user_managed_regions is non-empty, user-managed replication
                    is used; otherwise replication is automatic.
      kms_key_name = optional CMEK key. For automatic replication a single multi-region
                     key; for user-managed replication the key is applied to each
                     replica (keys must be valid in each region — see README).
  EOT
  type = map(object({
    labels = optional(map(string), {})
    replication = optional(object({
      automatic            = optional(bool, true)
      user_managed_regions = optional(list(string), [])
    }), {})
    kms_key_name = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name in keys(var.secrets) :
      can(regex("^[a-zA-Z0-9_-]{1,255}$", name))
    ])
    error_message = "each secret name must be 1-255 characters of letters, digits, hyphens or underscores."
  }
}

variable "secret_values" {
  description = <<-EOT
    Optional initial secret VALUES as secret_name => value. A google_secret_manager_secret_version
    is created ONLY for the names present here. Omit in production and set values out of
    band (console, CI with a privileged SA, or `gcloud secrets versions add`) to keep
    plaintext out of Terraform state. Every key must also exist in var.secrets.
  EOT
  type        = map(string)
  default     = {}
  sensitive   = true

  validation {
    condition = alltrue([
      for name in nonsensitive(keys(var.secret_values)) :
      contains(keys(var.secrets), name)
    ])
    error_message = "every key in secret_values must correspond to a secret declared in var.secrets."
  }
}

variable "secret_accessors" {
  description = <<-EOT
    Map of secret name => list of IAM members granted roles/secretmanager.secretAccessor
    on that secret (e.g. "serviceAccount:app@project.iam.gserviceaccount.com"). Every key
    must also exist in var.secrets.
  EOT
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for name in keys(var.secret_accessors) :
      contains(keys(var.secrets), name)
    ])
    error_message = "every key in secret_accessors must correspond to a secret declared in var.secrets."
  }
}

variable "enable_deletion_protection" {
  description = <<-EOT
    Prevent accidental destruction of this module's secrets.

    When true, a terraform_data guard resource is created with prevent_destroy = true.
    Terraform refuses to destroy the module while the guard exists. To intentionally
    remove protected secrets, first run:
      terraform state rm 'module.<name>.terraform_data.deletion_protection_guard'
  EOT
  type        = bool
  default     = true
}
