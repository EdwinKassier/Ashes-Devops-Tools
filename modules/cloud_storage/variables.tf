variable "project_id" {
  description = "The ID of the project"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "kms_key_name" {
  description = "Fully qualified KMS key name for bucket encryption. Format: projects/<project>/locations/<location>/keyRings/<keyring>/cryptoKeys/<key>"
  type        = string
  validation {
    condition     = can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be in the format: projects/<project>/locations/<location>/keyRings/<keyring>/cryptoKeys/<key>"
  }
}

variable "data_buckets" {
  description = <<-EOT
    Map of logical key to data bucket configuration. Each entry creates one GCS bucket.
    The bucket name is: "<project_id>-<name_suffix>".
    Example:
      data_buckets = {
        twitter_data_lake    = { name_suffix = "twitter-data-lake" }
        twitter_dataflow_meta = { name_suffix = "twitter-dataflow-meta" }
      }
  EOT
  type = map(object({
    name_suffix   = string
    force_destroy = optional(bool, false)
    # Soft-delete retention in seconds. Set to 0 to disable soft-delete (useful in dev/test).
    # Default 604800 = 7 days (GCS default).
    soft_delete_retention_seconds = optional(number, 604800)
    # Optional hard-delete lifecycle age in days. When set, objects are permanently deleted
    # after this many days. Leave null for indefinite retention (default).
    retention_days = optional(number, null)
  }))
  default = {}
}

variable "allowed_members" {
  description = "List of members with objectViewer read access to all data_buckets (e.g., ['user:user@example.com', 'group:admins@example.com', 'serviceAccount:sa@project.iam.gserviceaccount.com'])"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.allowed_members : can(regex("^(user|group|serviceAccount|domain|principal|principalSet):.+$", m))])
    error_message = "Each member must be prefixed with a valid IAM member type: user:, group:, serviceAccount:, domain:, principal:, or principalSet:."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in the logging bucket. Minimum 1 day."
  type        = number
  default     = 90
  validation {
    condition     = var.log_retention_days >= 1
    error_message = "log_retention_days must be at least 1."
  }
}

variable "labels" {
  description = "Labels to apply to all storage bucket resources in this module."
  type        = map(string)
  default     = {}
}
