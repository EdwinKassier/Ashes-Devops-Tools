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
  description = "ARN of the principal (role/user) granted key ADMINISTRATION on the CMK: management actions only (Enable/Disable, rotation, tagging, ScheduleKeyDeletion/CancelKeyDeletion, ...), no Encrypt/Decrypt/GenerateDataKey/ReEncrypt, no CreateGrant and — unless key_policy_admin_arns is empty — no PutKeyPolicy. REQUIRED to prevent locking the key out of management. Grant usage via key_user_arns."
  type        = string

  validation {
    condition     = length(trimspace(var.key_admin_arn)) > 0
    error_message = "key_admin_arn must be a non-empty string."
  }
}

variable "key_policy_admin_arns" {
  description = "Principal ARNs granted kms:PutKeyPolicy — and nothing else — on the CMK. Whoever can rewrite the key policy can grant itself kms:Decrypt, so set this to the break-glass role(s) and keep the pipeline out. When set, the CreateKey lockout safety check is bypassed (the caller is intentionally not a policy admin) and later Terraform key-policy changes must be applied as one of these principals. Empty (default) = legacy behaviour: key_admin_arn also holds PutKeyPolicy."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.key_policy_admin_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", a))])
    error_message = "key_policy_admin_arns entries must be account-qualified IAM role ARNs without wildcards."
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
  description = "Optional list of AWS service principals (e.g. sns.amazonaws.com, ssm.amazonaws.com, cloudwatch.amazonaws.com) granted general-usage (Encrypt/Decrypt/GenerateDataKey/etc.) on the CMK, scoped per service_principal_scope (default: the key's own account via aws:SourceAccount). Unlike log_service_principals these carry no CloudTrail EncryptionContext condition. Empty by default (no service-principal statement)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.service_principals : can(regex("[.]amazonaws[.]com$", p))])
    error_message = "Each service_principals entry must be an AWS service principal ending in .amazonaws.com."
  }
}

variable "service_principal_scope" {
  description = "Scope of the service_principals (ServiceUsage) grant. \"account\" (default): aws:SourceAccount = key_account_id, so only service calls on behalf of the key's own account can use it. \"organization\": aws:SourceOrgID = org_id — opt-in for keys that genuinely receive org-wide service writes; any org account could then use the key through those services."
  type        = string
  default     = "account"

  validation {
    condition     = contains(["account", "organization"], var.service_principal_scope)
    error_message = "service_principal_scope must be \"account\" or \"organization\"."
  }
}

variable "key_account_id" {
  description = "12-digit ID of the account the key lives in, used for the account-scoped ServiceUsage condition. Null (default) = the provider's account (aws_caller_identity)."
  type        = string
  default     = null

  validation {
    condition     = var.key_account_id == null || can(regex("^[0-9]{12}$", coalesce(var.key_account_id, "x")))
    error_message = "key_account_id must be null or a 12-digit AWS account ID."
  }
}

variable "enable_deletion_protection" {
  description = "Create a prevent_destroy guard that makes any plan which destroys or replaces the KMS key fail. Turning it off does not remove an existing guard: run terraform state rm on the guard first."
  type        = bool
  default     = true
}
