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
      ephemeral_value = when true, an initial version is created from the ephemeral
                        var.ephemeral_secret_values[name] instead of var.secret_values.
                        The flag lives here because the version set must stay
                        non-ephemeral (an ephemeral map cannot drive for_each).
  EOT
  type = map(object({
    labels = optional(map(string), {})
    replication = optional(object({
      automatic            = optional(bool, true)
      user_managed_regions = optional(list(string), [])
    }), {})
    kms_key_name    = optional(string)
    ephemeral_value = optional(bool, false)
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
    is created ONLY for the names present here, using the write-only secret_data_wo argument,
    so the plaintext is never stored in Terraform plan or state (Terraform >= 1.11). Pass an
    ephemeral value where possible. Every key must also exist in var.secrets.
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

  validation {
    condition = alltrue([
      for name in nonsensitive(keys(var.secret_values)) :
      !try(var.secrets[name].ephemeral_value, false)
    ])
    error_message = "a secret with ephemeral_value = true takes its value from ephemeral_secret_values, not secret_values."
  }
}

variable "ephemeral_secret_values" {
  description = <<-EOT
    Ephemeral initial secret VALUES as secret_name => value, for secrets declared in
    var.secrets with ephemeral_value = true. Written with the write-only secret_data_wo
    argument and never stored in plan or state; feed it from an ephemeral resource or an
    ephemeral root variable. Prefer this over secret_values, whose value must be known
    to (and is held in memory by) the calling configuration. Bump secret_value_versions
    to push a new value.
  EOT
  type        = map(string)
  default     = {}
  sensitive   = true
  ephemeral   = true

  validation {
    condition = alltrue([
      for name in keys(var.ephemeral_secret_values) :
      try(var.secrets[name].ephemeral_value, false)
    ])
    error_message = "every key in ephemeral_secret_values must name a secret in var.secrets with ephemeral_value = true."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.secrets : contains(keys(var.ephemeral_secret_values), name) if cfg.ephemeral_value
    ])
    error_message = "every secret with ephemeral_value = true needs an entry in ephemeral_secret_values."
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

variable "secret_value_versions" {
  description = "Per-secret write-only version counter (secret_name => integer, default 1). Write-only values are not diffed, so increment a secret's counter to push a new value from secret_values."
  type        = map(number)
  default     = {}

  validation {
    condition     = alltrue([for v in values(var.secret_value_versions) : v >= 1 && floor(v) == v])
    error_message = "secret_value_versions values must be positive integers."
  }
}
