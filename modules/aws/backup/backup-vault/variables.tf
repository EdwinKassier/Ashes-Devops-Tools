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

variable "allow_copy_from_organization_id" {
  description = "AWS Organizations ID (o-...). When set, a vault access policy lets principals in that organization copy recovery points into this vault (backup:CopyIntoBackupVault), so it can be the destination of the org BACKUP_POLICY copy actions. Null (default) = no vault access policy."
  type        = string
  default     = null

  validation {
    condition     = var.allow_copy_from_organization_id == null || can(regex("^o-[a-z0-9]{10,32}$", coalesce(var.allow_copy_from_organization_id, "x")))
    error_message = "allow_copy_from_organization_id must be null or an AWS Organizations ID (o- followed by 10-32 lowercase letters or digits)."
  }
}

variable "notification_topic_arn" {
  description = "SNS topic that receives this vault's failed backup, copy and restore events (restore-testing restores included) and RECOVERY_POINT_MODIFIED. Null (default) = no vault notifications. The topic policy must allow backup.amazonaws.com to publish, and a KMS-encrypted topic's key must allow it too."
  type        = string
  default     = null

  validation {
    condition     = var.notification_topic_arn == null || can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", coalesce(var.notification_topic_arn, "x")))
    error_message = "notification_topic_arn must be null or an SNS topic ARN."
  }
}

# -----------------------------------------------------------------------------
# Restore testing plan
# -----------------------------------------------------------------------------

variable "create_restore_testing" {
  description = "Create the restore testing plan, its selections and (when restore_testing_role_arn is null) the restore-testing role. Set false for a vault that receives no recovery points: testing it proves nothing."
  type        = bool
  default     = true
  nullable    = false
}

variable "restore_testing_resource_types" {
  description = "Resource types the restore testing plan restores from this vault, one selection each. EBS selects by the restore_testing_tag_key/value tag; every other type selects all protected resources of that type in the vault. Default [\"EBS\"]."
  type        = list(string)
  default     = ["EBS"]
  nullable    = false

  validation {
    condition     = length(var.restore_testing_resource_types) > 0 && alltrue([for t in var.restore_testing_resource_types : contains(["EBS", "EC2", "RDS", "Aurora", "S3", "DynamoDB", "EFS", "FSx", "DocumentDB", "Neptune"], t)])
    error_message = "restore_testing_resource_types must be a non-empty list of EBS, EC2, RDS, Aurora, S3, DynamoDB, EFS, FSx, DocumentDB, Neptune."
  }
}

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
  description = "Name of the EBS restore testing selection. Other resource types use <name>_<type in lower case>. AWS restricts this to alphanumeric characters and underscores."
  type        = string
  default     = "ebs_restore_test"

  validation {
    condition     = can(regex("^[0-9A-Za-z_]+$", var.restore_testing_selection_name))
    error_message = "restore_testing_selection_name may contain only alphanumeric characters and underscores."
  }
}

variable "restore_testing_role_arn" {
  description = "ARN of an existing IAM role AWS Backup assumes to perform restore testing jobs. Null (default) creates restore_testing_role_name here (trusting backup.amazonaws.com, with the AWS managed AWSBackupServiceRolePolicyForRestores policy)."
  type        = string
  default     = null

  validation {
    condition     = var.restore_testing_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.restore_testing_role_arn, "x")))
    error_message = "restore_testing_role_arn must be null or an account-qualified IAM role ARN."
  }
}

variable "restore_testing_role_name" {
  description = "Name of the restore-testing IAM role created when restore_testing_role_arn is null."
  type        = string
  default     = "aws-backup-restore-testing"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.restore_testing_role_name))
    error_message = "restore_testing_role_name must be a valid IAM role name (1-64 chars of [A-Za-z0-9+=,.@_-])."
  }
}

variable "partition" {
  description = "AWS partition for the managed-policy ARNs attached to the created restore-testing role (aws, aws-us-gov, aws-cn)."
  type        = string
  default     = "aws"

  validation {
    condition     = can(regex("^aws(-[a-z]+)*$", var.partition))
    error_message = "partition must be aws, aws-us-gov, aws-cn, ..."
  }
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

variable "permissions_boundary_arn" {
  description = "Permissions-boundary managed policy ARN set on every IAM role this module creates. Required when the roles are created by a member-account tfc-apply role with boundary propagation on (tfc-oidc-baseline enable_apply_boundary_propagation): pass arn:PARTITION:iam::ACCOUNT_ID:policy/tfc-apply-boundary. Null (default) = no boundary."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:[^:]+:iam::[^:]*:policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be null or an IAM managed policy ARN (arn:PARTITION:iam::ACCOUNT_ID:policy/NAME)."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
