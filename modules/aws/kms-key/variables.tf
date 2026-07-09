variable "alias" {
  description = "Alias for the CMK, without the \"alias/\" prefix (the module adds it). Used both for the aws_kms_alias name and the key description."
  type        = string

  validation {
    condition     = length(trimspace(var.alias)) > 0
    error_message = "alias must be a non-empty string."
  }
}

variable "deletion_window_in_days" {
  description = "Waiting period, in days, before the CMK is deleted after scheduling deletion. AWS permits 7-30."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "org_id" {
  description = "AWS Organizations organization ID (o-xxxxxxxxxx). Used in the aws:SourceOrgID condition that scopes log-service grants to this org."
  type        = string

  validation {
    condition     = length(trimspace(var.org_id)) > 0
    error_message = "org_id must be a non-empty string."
  }
}

variable "management_account_id" {
  description = "Organization management (payer) account ID. Used to scope the CloudTrail EncryptionContext condition to trails in that account."
  type        = string

  validation {
    condition     = length(trimspace(var.management_account_id)) > 0
    error_message = "management_account_id must be a non-empty string."
  }
}

variable "key_admin_arn" {
  description = "ARN of the principal (role/user) granted key administration (kms:*) on the CMK. REQUIRED to prevent locking the key out of management."
  type        = string

  validation {
    condition     = length(trimspace(var.key_admin_arn)) > 0
    error_message = "key_admin_arn must be a non-empty string."
  }
}

variable "log_service_principals" {
  description = "AWS log-delivery service principals granted GenerateDataKey/Decrypt/DescribeKey on the CMK, scoped by aws:SourceOrgID. CloudTrail additionally gets an EncryptionContext condition."
  type        = list(string)
  default     = ["cloudtrail.amazonaws.com", "config.amazonaws.com", "securitylake.amazonaws.com"]

  validation {
    condition     = alltrue([for p in var.log_service_principals : can(regex("[.]amazonaws[.]com$", p))])
    error_message = "Each log_service_principals entry must be an AWS service principal ending in .amazonaws.com."
  }
}

variable "key_users" {
  description = "Optional list of principal ARNs granted general-usage (Encrypt/Decrypt/GenerateDataKey/etc.) on the CMK. Empty by default (no general-usage statement)."
  type        = list(string)
  default     = []
}

variable "via_services" {
  description = "Optional list of kms:ViaService values that scope the general-usage grant for key_users (e.g. s3.eu-west-1.amazonaws.com). Never applied to the log-service grants."
  type        = list(string)
  default     = []
}
