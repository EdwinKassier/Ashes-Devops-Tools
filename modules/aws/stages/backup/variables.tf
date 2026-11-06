# -----------------------------------------------------------------------------
# Vault (BACKUP account)
# -----------------------------------------------------------------------------

variable "vault_name" {
  description = "Name of the AWS Backup vault created in the backup account. This is the cross-account naming contract: the management account's org BACKUP_POLICY targets the vault by this name."
  type        = string
  default     = "org-backup-vault"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt recovery points in the vault. Empty string uses the AWS-managed default Backup key."
  type        = string
  default     = ""
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

variable "changeable_for_days" {
  description = "Cooling-off window (days) during which the Compliance-mode Vault Lock can still be changed or deleted. After this window the lock is immutable (WORM). Must be at least 3."
  type        = number
  default     = 3

  validation {
    condition     = var.changeable_for_days >= 3
    error_message = "changeable_for_days must be at least 3 (AWS Compliance-mode Vault Lock minimum cooling-off period)."
  }
}

variable "restore_testing_role_arn" {
  description = "ARN of an existing IAM role (in the backup account) AWS Backup assumes to perform restore testing jobs. Null (default) creates aws-backup-restore-testing in the backup account."
  type        = string
  default     = null

  validation {
    condition     = var.restore_testing_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.restore_testing_role_arn, "x")))
    error_message = "restore_testing_role_arn must be null or an account-qualified IAM role ARN."
  }
}

# -----------------------------------------------------------------------------
# Organization BACKUP_POLICY (MANAGEMENT account)
# -----------------------------------------------------------------------------

variable "backup_role_arn" {
  description = "ARN of the IAM role AWS Backup assumes IN EACH MEMBER ACCOUNT to run the org backup plan's jobs, rendered into the org BACKUP_POLICY. May use the policy variable $account (arn:aws:iam::$account:role/<name>). Null (default): the stage deploys backup_role_name to every account under workloads_ou_id via a service-managed CloudFormation StackSet (auto-deploying to new accounts) and renders arn:aws:iam::$account:role/<backup_role_name>."
  type        = string
  default     = null

  validation {
    condition     = var.backup_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|[$]account):role/.+$", coalesce(var.backup_role_arn, "x")))
    error_message = "backup_role_arn must be null or an IAM role ARN whose account is a 12-digit ID or $account."
  }
}

variable "backup_role_name" {
  description = "Name of the member-account AWS Backup service role the StackSet deploys when backup_role_arn is null. Trusted by backup.amazonaws.com, with the AWS managed AWSBackupServiceRolePolicyForBackup and AWSBackupServiceRolePolicyForRestores policies."
  type        = string
  default     = "aws-backup-org-role"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.backup_role_name))
    error_message = "backup_role_name must be a valid IAM role name (1-64 chars of [A-Za-z0-9+=,.@_-])."
  }
}

variable "backup_role_stack_set_call_as" {
  description = "Whether the backup-role StackSet is managed as the management account (SELF) or a CloudFormation delegated administrator (DELEGATED_ADMIN). This stage's default provider is the management account, so SELF."
  type        = string
  default     = "SELF"

  validation {
    condition     = contains(["SELF", "DELEGATED_ADMIN"], var.backup_role_stack_set_call_as)
    error_message = "backup_role_stack_set_call_as must be SELF or DELEGATED_ADMIN."
  }
}

variable "workloads_ou_id" {
  description = "ID of the OU the org BACKUP_POLICY is attached to (typically the Workloads OU). Every account beneath it inherits the baseline backup plan."
  type        = string
}

variable "aws_region" {
  description = "AWS region the org backup plan copies recovery points into. Rendered into the templated BACKUP_POLICY's regions @@assign."
  type        = string
  default     = "eu-west-2"
}
