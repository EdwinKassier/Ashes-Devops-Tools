variable "log_archive_bucket_name" {
  description = "Deterministic name of the central log-archive bucket. This is a cross-root naming contract: it must match the name the B3 SCP references."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket_name)) > 0
    error_message = "log_archive_bucket_name must be a non-empty string."
  }
}

variable "kms_key_arn" {
  description = "ARN of the CMK used for SSE-KMS default encryption on the bucket (e.g. the aws/kms-key module's key_arn output)."
  type        = string

  validation {
    condition     = length(trimspace(var.kms_key_arn)) > 0
    error_message = "kms_key_arn must be a non-empty string."
  }
}

variable "org_id" {
  description = "AWS Organizations organization ID (o-xxxxxxxxxx). Used in the aws:SourceOrgID condition that scopes log-delivery grants in the bucket policy."
  type        = string

  validation {
    condition     = length(trimspace(var.org_id)) > 0
    error_message = "org_id must be a non-empty string."
  }
}

variable "object_lock_mode" {
  description = "Default S3 Object Lock retention mode. COMPLIANCE is WORM against all principals (incl. root) and blocks destroy until retention lapses; GOVERNANCE is bypassable by privileged principals."
  type        = string
  default     = "COMPLIANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be one of GOVERNANCE or COMPLIANCE."
  }
}

variable "retention_days" {
  description = "Default Object Lock retention period, in days. Also drives lifecycle expiration."
  type        = number
  default     = 365

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days must be at least 1."
  }
}
