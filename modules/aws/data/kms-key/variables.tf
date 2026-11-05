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
  description = "ARN of the principal (role/user) granted key ADMINISTRATION on the CMK: management actions only (PutKeyPolicy, Enable/Disable, rotation, tagging, ScheduleKeyDeletion/CancelKeyDeletion, ...), no Encrypt/Decrypt/GenerateDataKey/ReEncrypt and no CreateGrant. REQUIRED to prevent locking the key out of management. Grant usage via key_user_arns."
  type        = string

  validation {
    condition     = length(trimspace(var.key_admin_arn)) > 0
    error_message = "key_admin_arn must be a non-empty string."
  }
}

variable "log_service_principals" {
  description = "AWS log-delivery service principals granted GenerateDataKey/Decrypt/DescribeKey on the CMK, scoped by aws:SourceOrgID. CloudTrail additionally gets an EncryptionContext condition."
  type        = list(string)
  default     = ["cloudtrail.amazonaws.com", "config.amazonaws.com", "securitylake.amazonaws.com", "delivery.logs.amazonaws.com"]

  validation {
    condition     = alltrue([for p in var.log_service_principals : can(regex("[.]amazonaws[.]com$", p))])
    error_message = "Each log_service_principals entry must be an AWS service principal ending in .amazonaws.com."
  }
}

variable "key_user_arns" {
  description = "Optional list of principal ARNs granted key USAGE (Encrypt/Decrypt/ReEncrypt/GenerateDataKey/DescribeKey) on the CMK. Kept separate from key_admin_arn, which receives management actions only. Empty by default (no general-usage statement)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.key_user_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/.+|user/.+)$", a))])
    error_message = "Each key_user_arns entry must be an account-qualified IAM role/user/root ARN (no wildcards in the account)."
  }
}

variable "enable_protection_tag" {
  description = "Tag the key <protection_tag_key> = \"true\" so the organization deny-tamper SCP blocks ScheduleKeyDeletion/DisableKey/DisableKeyRotation and protection-tag removal except via break-glass. Default false; the security stage enables it for the log-archive, forensics and security-tooling keys."
  type        = bool
  default     = false
}

variable "protection_tag_key" {
  description = "Tag key used when enable_protection_tag is true. Must match the organization-policy module's kms_protection_tag_key."
  type        = string
  default     = "protected"

  validation {
    condition     = can(regex("^[A-Za-z0-9 _.:/=+@-]{1,128}$", var.protection_tag_key)) && !startswith(var.protection_tag_key, "aws:")
    error_message = "protection_tag_key must be a valid AWS tag key (1-128 chars, not starting with aws:)."
  }
}

variable "tags" {
  description = "Additional tags applied to the CMK."
  type        = map(string)
  default     = {}
}

variable "via_services" {
  description = "Optional list of kms:ViaService values that scope the general-usage grant for key_user_arns (e.g. s3.eu-west-1.amazonaws.com). Never applied to the log-service grants."
  type        = list(string)
  default     = []
}

variable "service_principals" {
  description = "Optional list of AWS service principals (e.g. sns.amazonaws.com, ssm.amazonaws.com, cloudwatch.amazonaws.com) granted general-usage (Encrypt/Decrypt/GenerateDataKey/etc.) on the CMK, scoped by aws:SourceOrgID so only calls originating within this org can use the key. Unlike log_service_principals these carry no CloudTrail EncryptionContext condition. Empty by default (no service-principal statement)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.service_principals : can(regex("[.]amazonaws[.]com$", p))])
    error_message = "Each service_principals entry must be an AWS service principal ending in .amazonaws.com."
  }
}
