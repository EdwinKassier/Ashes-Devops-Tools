variable "project_id" {
  description = "The ID of the project where the Cloud Audit Logs will be configured"
  type        = string
}

variable "bucket_location" {
  description = "The location of the bucket that will store audit logs"
  type        = string
  default     = "US"
}

variable "log_retention_days" {
  description = "The number of days to retain audit logs in the storage bucket (minimum 1)"
  type        = number
  default     = 365

  validation {
    condition     = var.log_retention_days >= 1
    error_message = "log_retention_days must be at least 1."
  }
}

variable "force_destroy_bucket" {
  description = "When deleting the bucket, automatically delete all objects"
  type        = bool
  default     = false
}

variable "kms_key_name" {
  description = "The KMS key name to encrypt the audit logs bucket (optional). Format: projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/.+/locations/.+/keyRings/.+/cryptoKeys/.+$", var.kms_key_name))
    error_message = "kms_key_name must be in format: projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}."
  }
}

variable "bigquery_kms_key_name" {
  description = "The KMS key name to encrypt the optional BigQuery audit analytics dataset. Format: projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}"
  type        = string
  default     = null

  validation {
    condition     = var.bigquery_kms_key_name == null || can(regex("^projects/.+/locations/.+/keyRings/.+/cryptoKeys/.+$", var.bigquery_kms_key_name))
    error_message = "bigquery_kms_key_name must be in format: projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}."
  }
}

variable "org_id" {
  description = "Organization ID for org-level log sink (optional). When provided, creates an org-level sink that captures audit logs from all projects."
  type        = string
  default     = null

  validation {
    condition     = var.org_id == null || can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be a numeric organization ID (digits only, e.g. \"123456789\")."
  }
}

# =============================================================================
# BIGQUERY LOG ANALYTICS (Optional)
# =============================================================================

variable "enable_bigquery_analytics" {
  description = "Enable BigQuery sink for log analytics. Creates a BigQuery dataset and org-level sink for querying audit logs."
  type        = bool
  default     = false
}

variable "bigquery_location" {
  description = "Location for the BigQuery dataset. Should match or be compatible with bucket_location."
  type        = string
  default     = "US"
}

variable "bigquery_retention_days" {
  description = "Number of days to retain audit logs in BigQuery (via partition expiration). Minimum 1."
  type        = number
  default     = 365

  validation {
    condition     = var.bigquery_retention_days >= 1
    error_message = "bigquery_retention_days must be at least 1."
  }
}
