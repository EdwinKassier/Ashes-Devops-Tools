variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for the Firebase web-app storage resources. Required only when `web_display_name` is set (a web app is created); ignored otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.web_display_name == "" || var.region != null
    error_message = "region is required when web_display_name is set (a Firebase web app is created)."
  }
}

# Apple App Variables
variable "apple_display_name" {
  description = "Display name for the Apple app"
  type        = string
  default     = ""
}

variable "apple_bundle_id" {
  description = "Bundle ID for the Apple app"
  type        = string
  default     = ""
}

variable "apple_app_store_id" {
  description = "App Store ID for the Apple app"
  type        = string
  default     = ""
}

variable "apple_team_id" {
  description = "Apple Team ID for the Apple app (10-character uppercase alphanumeric)"
  type        = string
  default     = ""

  validation {
    condition     = var.apple_team_id == "" || can(regex("^[A-Z0-9]{10}$", var.apple_team_id))
    error_message = "apple_team_id must be empty or a 10-character uppercase alphanumeric Apple Team ID."
  }
}

# Android App Variables
variable "android_display_name" {
  description = "Display name for the Android app"
  type        = string
  default     = ""
}

variable "android_package_name" {
  description = "Package name for the Android app"
  type        = string
  default     = ""
}

variable "android_sha1_hashes" {
  description = "List of SHA-1 certificate fingerprints for the Android app (40 hex characters, colon-separated pairs accepted)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for h in var.android_sha1_hashes :
      can(regex("^[0-9A-Fa-f]{40}$", h)) || can(regex("^([0-9A-Fa-f]{2}:){19}[0-9A-Fa-f]{2}$", h))
    ])
    error_message = "Each android_sha1_hashes entry must be a 40-character hex string or colon-separated hex pairs (e.g., 'AA:BB:CC:...')."
  }
}

variable "android_sha256_hashes" {
  description = "List of SHA-256 certificate fingerprints for the Android app (64 hex characters, colon-separated pairs accepted)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for h in var.android_sha256_hashes :
      can(regex("^[0-9A-Fa-f]{64}$", h)) || can(regex("^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$", h))
    ])
    error_message = "Each android_sha256_hashes entry must be a 64-character hex string or colon-separated hex pairs."
  }
}

# Web App Variables
variable "web_display_name" {
  description = "Display name for the web app"
  type        = string
  default     = ""
}

variable "kms_key_name" {
  description = "Optional customer-managed KMS key used for the Firebase web config bucket"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be a valid KMS key resource name: projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}
