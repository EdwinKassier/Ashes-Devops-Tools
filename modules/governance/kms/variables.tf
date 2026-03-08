variable "project_id" {
  description = "Project ID where the Keyring will be created"
  type        = string
}

variable "keyring_name" {
  description = "Name of the KMS Keyring"
  type        = string
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
    condition = alltrue([
      for key in values(var.keys) :
      try(
        tonumber(replace(coalesce(try(key.rotation_period, null), "7776000s"), "s", "")) >= 86400 &&
        tonumber(replace(coalesce(try(key.rotation_period, null), "7776000s"), "s", "")) <= 7776000,
        false
      )
    ])
    error_message = "Every KMS key rotation_period must be between 86400s (1 day) and 7776000s (90 days)."
  }
}

variable "labels" {
  description = "Labels for all keys"
  type        = map(string)
  default     = {}
}
