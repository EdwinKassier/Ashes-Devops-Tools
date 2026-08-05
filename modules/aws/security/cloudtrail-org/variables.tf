variable "trail_name" {
  description = "Name of the organization CloudTrail trail."
  type        = string
  default     = "org-trail"

  validation {
    condition     = length(trimspace(var.trail_name)) > 0
    error_message = "trail_name must be a non-empty string."
  }
}

variable "log_archive_bucket" {
  description = "Name of the central Log-Archive S3 bucket that receives the trail's log files. This bucket lives in the Log-Archive account (a different account from the trail owner); its resource policy authorizes CloudTrail delivery."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket)) > 0
    error_message = "log_archive_bucket must be a non-empty S3 bucket name."
  }
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the CloudTrail log files delivered to the Log-Archive bucket."
  type        = string

  validation {
    condition     = length(trimspace(var.kms_key_arn)) > 0
    error_message = "kms_key_arn must be a non-empty KMS key ARN."
  }
}
