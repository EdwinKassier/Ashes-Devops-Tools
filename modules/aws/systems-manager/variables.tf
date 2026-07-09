# -----------------------------------------------------------------------------
# Session Manager preferences
# -----------------------------------------------------------------------------

variable "session_document_name" {
  description = "Name of the custom Session Manager preferences document. A custom name (not the reserved SSM-SessionManagerRunShell) keeps preferences under Terraform control per account."
  type        = string
  default     = "SessionManagerPreferences"

  validation {
    condition     = length(trimspace(var.session_document_name)) > 0
    error_message = "session_document_name must be a non-empty string."
  }
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket that receives Session Manager session logs."
  type        = string

  validation {
    condition     = length(trimspace(var.log_bucket_name)) > 0
    error_message = "log_bucket_name must be a non-empty S3 bucket name."
  }
}

variable "cloudwatch_log_group" {
  description = "CloudWatch Logs log group name that receives Session Manager session logs."
  type        = string
  default     = "/aws/ssm/session-logs"
}

variable "kms_key_id" {
  description = "KMS key ID or ARN used to encrypt Session Manager sessions and logs."
  type        = string

  validation {
    condition     = length(trimspace(var.kms_key_id)) > 0
    error_message = "kms_key_id must be a non-empty KMS key ID or ARN."
  }
}

# -----------------------------------------------------------------------------
# Patch baseline
# -----------------------------------------------------------------------------

variable "patch_baseline_name" {
  description = "Name of the SSM patch baseline."
  type        = string
  default     = "org-patch-baseline"

  validation {
    condition     = length(trimspace(var.patch_baseline_name)) > 0
    error_message = "patch_baseline_name must be a non-empty string."
  }
}

variable "patch_operating_system" {
  description = "Operating system the patch baseline targets. Also used to set the account default patch baseline for that OS."
  type        = string
  default     = "AMAZON_LINUX_2"

  validation {
    condition = contains(
      ["AMAZON_LINUX", "AMAZON_LINUX_2", "AMAZON_LINUX_2023", "UBUNTU", "REDHAT_ENTERPRISE_LINUX", "WINDOWS"],
      var.patch_operating_system
    )
    error_message = "patch_operating_system must be one of: AMAZON_LINUX, AMAZON_LINUX_2, AMAZON_LINUX_2023, UBUNTU, REDHAT_ENTERPRISE_LINUX, WINDOWS."
  }
}

variable "patch_approve_after_days" {
  description = "Number of days to wait after a patch is released before auto-approving it."
  type        = number
  default     = 7

  validation {
    condition     = var.patch_approve_after_days >= 0 && var.patch_approve_after_days <= 360
    error_message = "patch_approve_after_days must be between 0 and 360."
  }
}

# -----------------------------------------------------------------------------
# Software inventory
# -----------------------------------------------------------------------------

variable "inventory_association_name" {
  description = "Name of the software-inventory State Manager association."
  type        = string
  default     = "org-inventory"

  validation {
    condition     = length(trimspace(var.inventory_association_name)) > 0
    error_message = "inventory_association_name must be a non-empty string."
  }
}

variable "inventory_schedule" {
  description = "Schedule expression (rate or cron) for the software-inventory association."
  type        = string
  default     = "rate(1 day)"

  validation {
    condition     = length(trimspace(var.inventory_schedule)) > 0
    error_message = "inventory_schedule must be a non-empty schedule expression."
  }
}
