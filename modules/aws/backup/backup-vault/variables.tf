# -----------------------------------------------------------------------------
# Vault
# -----------------------------------------------------------------------------

variable "vault_name" {
  description = "Name of the AWS Backup vault."
  type        = string
  default     = "org-backup-vault"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt recovery points in the vault. Empty string uses the AWS-managed default Backup key."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Vault Lock (Compliance-mode WORM)
# -----------------------------------------------------------------------------

variable "changeable_for_days" {
  description = "Cooling-off window (days) during which the Vault Lock can still be changed or deleted. A non-null value enables Compliance mode (WORM); after this window the lock is immutable. Must be at least 3."
  type        = number
  default     = 3

  validation {
    condition     = var.changeable_for_days >= 3
    error_message = "changeable_for_days must be at least 3 (AWS Compliance-mode Vault Lock minimum cooling-off period)."
  }
}

variable "min_retention_days" {
  description = "Minimum retention (days) enforced on every recovery point stored in the vault. Recovery points cannot be deleted before this age."
  type        = number
  default     = 7
}

variable "max_retention_days" {
  description = "Maximum retention (days) allowed for recovery points stored in the vault."
  type        = number
  default     = 3650
}

# -----------------------------------------------------------------------------
# Restore testing plan
# -----------------------------------------------------------------------------

variable "restore_testing_plan_name" {
  description = "Name of the AWS Backup restore testing plan. AWS restricts this to alphanumeric characters and underscores."
  type        = string
  default     = "org_restore_test"

  validation {
    condition     = can(regex("^[0-9A-Za-z_]+$", var.restore_testing_plan_name))
    error_message = "restore_testing_plan_name may contain only alphanumeric characters and underscores."
  }
}

variable "selection_window_days" {
  description = "Number of days from which to select recovery points for restore testing (LATEST_WITHIN_WINDOW). Must be at least 1."
  type        = number
  default     = 7

  validation {
    condition     = var.selection_window_days >= 1
    error_message = "selection_window_days must be at least 1."
  }
}

variable "restore_testing_schedule" {
  description = "Cron schedule expression for the restore testing plan."
  type        = string
  default     = "cron(0 5 ? * SUN *)"
}

variable "start_window_hours" {
  description = "Number of hours in which restore testing jobs must start before being cancelled."
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Restore testing selection
# -----------------------------------------------------------------------------

variable "restore_testing_selection_name" {
  description = "Name of the restore testing selection (the resource set that gets restored). AWS restricts this to alphanumeric characters and underscores."
  type        = string
  default     = "ebs_restore_test"

  validation {
    condition     = can(regex("^[0-9A-Za-z_]+$", var.restore_testing_selection_name))
    error_message = "restore_testing_selection_name may contain only alphanumeric characters and underscores."
  }
}

variable "restore_testing_role_arn" {
  description = "ARN of the IAM role AWS Backup assumes to perform restore testing jobs."
  type        = string
}

variable "restore_testing_tag_key" {
  description = "Resource tag key used to select EBS recovery points for restore testing. Combined with restore_testing_tag_value in a protected_resource_conditions string_equals match."
  type        = string
  default     = "backup"
}

variable "restore_testing_tag_value" {
  description = "Resource tag value used to select EBS recovery points for restore testing."
  type        = string
  default     = "true"
}
