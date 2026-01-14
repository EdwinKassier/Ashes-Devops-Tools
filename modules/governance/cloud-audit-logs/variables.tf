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
  description = "The number of days to retain audit logs in the storage bucket"
  type        = number
  default     = 365
}

variable "force_destroy_bucket" {
  description = "When deleting the bucket, automatically delete all objects"
  type        = bool
  default     = false
}

variable "kms_key_name" {
  description = "The KMS key name to encrypt the audit logs bucket (optional)"
  type        = string
  default     = null
}

variable "org_id" {
  description = "Organization ID for org-level log sink (optional). When provided, creates an org-level sink that captures audit logs from all projects."
  type        = string
  default     = null
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
  description = "Number of days to retain audit logs in BigQuery (via partition expiration)."
  type        = number
  default     = 365
}
