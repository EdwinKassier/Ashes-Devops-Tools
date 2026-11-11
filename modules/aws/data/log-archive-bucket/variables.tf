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

variable "access_log_bucket" {
  description = "Existing bucket to receive the log archive's S3 server access logs (it must not use SSE-KMS default encryption or an Object Lock default retention). Empty (default) creates a companion <log_archive_bucket_name>-access-logs bucket with SSE-S3 and no Object Lock."
  type        = string
  default     = ""

  validation {
    condition     = var.access_log_bucket != var.log_archive_bucket_name
    error_message = "access_log_bucket must not be the log-archive bucket itself: S3 cannot deliver access logs to a bucket with SSE-KMS default encryption or an Object Lock default retention."
  }
}

variable "access_log_prefix" {
  description = "Key prefix for S3 server access logs."
  type        = string
  default     = "s3-access-logs/"
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "access_log_retention_days" {
  description = "Days the companion access-log bucket keeps S3 server access logs before they expire. Ignored when access_log_bucket names an existing bucket."
  type        = number
  default     = 365

  validation {
    condition     = var.access_log_retention_days >= 1
    error_message = "access_log_retention_days must be at least 1."
  }
}

variable "cloudtrail_trail_account_id" {
  description = "Account ID that owns the organization trail (the management account, also when a CloudTrail delegated administrator manages the trail). When set, the CloudTrail grants also require aws:SourceArn to match arn:<partition>:cloudtrail:*:<id>:trail/*. Empty (default) scopes them by aws:SourceOrgID only."
  type        = string
  default     = ""

  validation {
    condition     = var.cloudtrail_trail_account_id == "" || can(regex("^[0-9]{12}$", var.cloudtrail_trail_account_id))
    error_message = "cloudtrail_trail_account_id must be empty or a 12-digit AWS account ID."
  }
}

variable "enable_deletion_protection" {
  description = "Create a prevent_destroy guard that makes any plan which destroys or replaces the log-archive bucket fail. Turning it off does not remove an existing guard: run terraform state rm on the guard first."
  type        = bool
  default     = true
}
