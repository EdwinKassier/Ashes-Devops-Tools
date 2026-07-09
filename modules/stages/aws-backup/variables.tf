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
  description = "ARN of the IAM role (in the backup account) AWS Backup assumes to perform restore testing jobs."
  type        = string
}

# -----------------------------------------------------------------------------
# Organization BACKUP_POLICY (MANAGEMENT account)
# -----------------------------------------------------------------------------

variable "backup_role_arn" {
  description = "ARN of the IAM role AWS Backup assumes to run backup jobs for the resources selected by the org backup plan. Rendered into the org BACKUP_POLICY."
  type        = string
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
