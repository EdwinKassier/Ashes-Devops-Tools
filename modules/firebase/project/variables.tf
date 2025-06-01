variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
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
  description = "Apple Team ID for the Apple app"
  type        = string
  default     = ""
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
  description = "List of SHA-1 hashes for the Android app"
  type        = list(string)
  default     = []
}

variable "android_sha256_hashes" {
  description = "List of SHA-256 hashes for the Android app"
  type        = list(string)
  default     = []
}

# Web App Variables
variable "web_display_name" {
  description = "Display name for the web app"
  type        = string
  default     = ""
}
