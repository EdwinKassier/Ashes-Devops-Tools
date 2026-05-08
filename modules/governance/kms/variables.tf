variable "project_id" {
  description = "Project ID where the Keyring will be created (6-30 characters, lowercase alphanumeric and hyphens)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "keyring_name" {
  description = "Name of the KMS Keyring (1-63 alphanumeric characters, hyphens, and underscores)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,63}$", var.keyring_name))
    error_message = "keyring_name must be 1-63 characters containing only alphanumeric characters, hyphens, and underscores."
  }
}

variable "location" {
  description = "Location for the Keyring (region or 'global')"
  type        = string
  default     = "global"
}

variable "keys" {
  description = "Map of CryptoKeys to create"
  type = map(object({
    rotation_period      = optional(string, "7776000s") # 90 days
    purpose              = optional(string, "ENCRYPT_DECRYPT")
    algorithm            = optional(string, "GOOGLE_SYMMETRIC_ENCRYPTION")
    protection_level     = optional(string, "SOFTWARE")
    labels               = optional(map(string), {})
    encrypter_decrypters = optional(list(string), [])
  }))
  default = {}

  validation {
    # First guard: format must be "<N>s" where N is a positive integer.
    # This rejects "90d", "P90D", "7776000" (no suffix), etc. before numeric parsing.
    condition = alltrue([
      for key in values(var.keys) :
      can(regex("^[0-9]+s$", coalesce(try(key.rotation_period, null), "7776000s")))
    ])
    error_message = "Every KMS key rotation_period must be in the format '<N>s' (e.g. '7776000s' for 90 days). ISO 8601 durations and day/hour suffixes are not accepted."
  }

  validation {
    # Second guard: numeric range check (safe to do after format is guaranteed above).
    condition = alltrue([
      for key in values(var.keys) :
      tonumber(trimsuffix(coalesce(try(key.rotation_period, null), "7776000s"), "s")) >= 86400 &&
      tonumber(trimsuffix(coalesce(try(key.rotation_period, null), "7776000s"), "s")) <= 7776000
    ])
    error_message = "Every KMS key rotation_period must be between 86400s (1 day) and 7776000s (90 days)."
  }
}

variable "labels" {
  description = "Labels for all keys"
  type        = map(string)
  default     = {}
}
