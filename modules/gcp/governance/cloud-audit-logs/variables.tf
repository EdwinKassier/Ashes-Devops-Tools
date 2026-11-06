variable "project_id" {
  description = "The ID of the project where the Cloud Audit Logs will be configured"
  type        = string
}

variable "sink_name" {
  description = "Name of the project-level log sink. Override when calling the module more than once in the same project."
  type        = string
  default     = "audit-logs-sink"
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

variable "enable_bucket_lock" {
  description = "Opt-in WORM lock: apply a LOCKED retention policy of log_retention_days to the audit-log bucket, making objects undeletable before the window elapses (even by an admin). Default false preserves the current operator-correctable behaviour. A locked retention policy is IRREVERSIBLE — enable only for compliance regimes that require tamper-proof retention."
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "Soft-delete retention (days) on the audit-log buckets: deleted or overwritten objects stay restorable for this window. GCS accepts 7-90 days, or 0 to disable. Default 30."
  type        = number
  default     = 30

  validation {
    condition     = var.soft_delete_retention_days == 0 || (var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90)
    error_message = "soft_delete_retention_days must be 0 (disabled) or between 7 and 90."
  }
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

# =============================================================================
# CLOUD LOGGING LOG ANALYTICS
# =============================================================================

variable "enable_log_analytics" {
  description = "With org_id set, route every org audit log into a Cloud Logging log bucket with Log Analytics enabled (and, with enable_log_analytics_linked_dataset, a linked read-only BigQuery dataset). Default true."
  type        = bool
  default     = true
}

variable "enable_log_analytics_linked_dataset" {
  description = "Create the linked BigQuery dataset on the Log Analytics bucket (query audit logs from BigQuery without copying them). Default true."
  type        = bool
  default     = true
}

variable "log_analytics_bucket_id" {
  description = "ID of the Log Analytics log bucket."
  type        = string
  default     = "org-audit-analytics"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,100}$", var.log_analytics_bucket_id))
    error_message = "log_analytics_bucket_id must be 1-100 letters, digits, '_' or '-'."
  }
}

variable "log_analytics_link_id" {
  description = "ID of the linked BigQuery dataset (letters, digits and underscores only; it becomes the BigQuery dataset ID)."
  type        = string
  default     = "org_audit_analytics"

  validation {
    condition     = can(regex("^[A-Za-z0-9_]{1,100}$", var.log_analytics_link_id))
    error_message = "log_analytics_link_id must be 1-100 letters, digits or underscores."
  }
}

variable "log_analytics_location" {
  description = "Location of the Log Analytics bucket (a region, or global/us/eu). Null = bucket_location (lower-cased)."
  type        = string
  default     = null
}

variable "log_analytics_retention_days" {
  description = "Retention of the Log Analytics bucket in days (1-3650). Default 400 (CIS GCP 2.x recommends at least a year)."
  type        = number
  default     = 400

  validation {
    condition     = var.log_analytics_retention_days >= 1 && var.log_analytics_retention_days <= 3650
    error_message = "log_analytics_retention_days must be between 1 and 3650."
  }
}

variable "log_analytics_kms_key_name" {
  description = "Optional CMEK for the Log Analytics bucket. The key must be in the bucket's location and the project's Cloud Logging service account (google_logging_project_settings / gcloud logging settings describe) needs roles/cloudkms.cryptoKeyEncrypterDecrypter on it before apply. Null = Google-managed encryption."
  type        = string
  default     = null

  validation {
    condition     = var.log_analytics_kms_key_name == null || can(regex("^projects/.+/locations/.+/keyRings/.+/cryptoKeys/.+$", var.log_analytics_kms_key_name))
    error_message = "log_analytics_kms_key_name must be in format: projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}."
  }
}
