# -----------------------------------------------------------------------------
# Vault (BACKUP account)
# -----------------------------------------------------------------------------

variable "vault_name" {
  description = "Name of the AWS Backup vault created in the backup account. This is the cross-account naming contract: the org BACKUP_POLICY targets a vault of this name in each member account, which the member-account StackSet creates (aws-organization member_backup_vault_name must match)."
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

variable "tfc_apply_boundary_policy_name" {
  description = "Name of the tfc-apply permissions-boundary managed policy (tfc-oidc-baseline apply_boundary_policy_name). Every IAM role this stage creates in the backup account (the restore-testing role) gets permissions_boundary = arn:PARTITION:iam::ACCOUNT_ID:policy/NAME, derived from that account's provider, which the member-account tfc-apply role requires when boundary propagation is on. Null = create roles without a boundary."
  type        = string
  default     = "tfc-apply-boundary"

  validation {
    condition     = var.tfc_apply_boundary_policy_name == null || can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.tfc_apply_boundary_policy_name))
    error_message = "tfc_apply_boundary_policy_name must be null or a valid IAM policy name (1-128 chars of [A-Za-z0-9+=,.@_-])."
  }
}

variable "create_backup_role_stack_set" {
  description = "Deploy the member-account Backup service role (backup_role_name) from THIS stage through a service-managed StackSet. Default false: aws-organization deploys it (create_backup_service_role there), so the least-privilege aws-backup management role needs no CloudFormation rights. Set true only when aws-backup applies as the phase-0 management role."
  type        = bool
  default     = false
}

variable "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn) for the member Backup role ARN rendered into the BACKUP_POLICY."
  type        = string
  default     = "aws"
}

# -----------------------------------------------------------------------------
# Retention and central copy
# -----------------------------------------------------------------------------

variable "retention_days" {
  description = "Days the org BACKUP_POLICY daily rule keeps each recovery point in the member vault."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days must be at least 1."
  }
}

variable "enable_central_copy" {
  description = "Copy every member recovery point to a new CMK-encrypted, Compliance-mode Vault-Locked copy vault (copy_vault_name) in the backup account. Also enables org-wide cross-account backup in the management account, points the BACKUP_POLICY at the <vault_name>-cmk member vault (aws-organization member_backup_vault_encryption = cmk must have created it) and moves restore testing to the copy vault. IRREVERSIBLE after changeable_for_days: the lock cannot be removed and copies cannot be deleted before min_retention_days. Default false."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.enable_central_copy || (var.organization_id != null && can(regex("^[0-9]{12}$", coalesce(var.backup_account_id, "-"))))
    error_message = "enable_central_copy needs organization_id (the copy vault admits copies from that organization) and a 12-digit backup_account_id."
  }

  validation {
    condition     = !var.enable_central_copy || var.copy_vault_kms_key_arn != null || can(regex("^[0-9]{12}$", coalesce(var.management_account_id, "-")))
    error_message = "enable_central_copy without copy_vault_kms_key_arn creates the copy vault key, which needs a 12-digit management_account_id."
  }

  validation {
    condition     = !var.enable_central_copy || !var.create_backup_role_stack_set
    error_message = "enable_central_copy needs the aws-organization member StackSet (it creates the <vault_name>-cmk member vault); the legacy create_backup_role_stack_set = true creates only <vault_name>."
  }
}

variable "organization_id" {
  description = "AWS Organizations ID (o-...). The copy vault's access policy admits copies from principals in this organization only. Needed when enable_central_copy is true."
  type        = string
  default     = null

  validation {
    condition     = var.organization_id == null || can(regex("^o-[a-z0-9]{10,32}$", coalesce(var.organization_id, "x")))
    error_message = "organization_id must be null or an AWS Organizations ID (o- followed by 10-32 lowercase letters or digits)."
  }
}

variable "management_account_id" {
  description = "12-digit management account ID, used by the copy vault key module. Needed when enable_central_copy is true and copy_vault_kms_key_arn is null."
  type        = string
  default     = null
}

variable "backup_account_id" {
  description = "12-digit ID of the backup account (the aws.backup provider's account). The copy destination ARN and the copy vault key policy use it. Needed when enable_central_copy is true."
  type        = string
  default     = null
}

variable "copy_vault_name" {
  description = "Name of the locked central copy vault in the backup account."
  type        = string
  default     = "org-backup-copy-vault"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{2,50}$", var.copy_vault_name))
    error_message = "copy_vault_name must be 2-50 letters, digits, hyphens or underscores."
  }
}

variable "copy_vault_kms_key_arn" {
  description = "ARN of an existing customer managed key in the backup account for the copy vault. Null (default) creates one (alias backup-copy-vault): rotating, tagged protected = true, usable by backup-account principals only through AWS Backup and the restore services."
  type        = string
  default     = null

  validation {
    condition     = var.copy_vault_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", coalesce(var.copy_vault_kms_key_arn, "x")))
    error_message = "copy_vault_kms_key_arn must be null or a KMS key ARN."
  }
}

variable "copy_vault_notification_topic_arn" {
  description = "SNS topic in the backup account that receives the copy vault's failed backup, copy and restore events (restore-testing restores included) and RECOVERY_POINT_MODIFIED. Null (default) = no vault notifications. Used only with enable_central_copy. The topic policy (and the key policy of a KMS-encrypted topic) must allow backup.amazonaws.com to publish."
  type        = string
  default     = null

  validation {
    condition     = var.copy_vault_notification_topic_arn == null || can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", coalesce(var.copy_vault_notification_topic_arn, "x")))
    error_message = "copy_vault_notification_topic_arn must be null or an SNS topic ARN."
  }
}

variable "copy_vault_key_admin_arn" {
  description = "Principal granted key administration (no usage, no kms:PutKeyPolicy) on the created copy vault key. Null = the backup account's tfc-apply role, the role that applies this stage there."
  type        = string
  default     = null

  validation {
    condition     = var.copy_vault_key_admin_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", coalesce(var.copy_vault_key_admin_arn, "x")))
    error_message = "copy_vault_key_admin_arn must be null or an account-qualified IAM role or user ARN."
  }
}

variable "copy_vault_key_policy_admin_role_name" {
  description = "Role name in the backup account granted kms:PutKeyPolicy, and nothing else, on the created copy vault key. Default break-glass: the member break-glass role aws-organization deploys (enable_member_break_glass_role); it must exist before the key is created. Null = the key admin also holds kms:PutKeyPolicy."
  type        = string
  default     = "break-glass"

  validation {
    condition     = var.copy_vault_key_policy_admin_role_name == null || can(regex("^([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]{1,64}$", coalesce(var.copy_vault_key_policy_admin_role_name, "x")))
    error_message = "copy_vault_key_policy_admin_role_name must be null or an IAM role name without wildcards (optionally path-prefixed)."
  }
}

variable "copy_retention_days" {
  description = "Days each copy is kept in the central copy vault. Must lie between min_retention_days and max_retention_days (the copy vault's Vault Lock), or every copy job fails."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = !var.enable_central_copy || (var.copy_retention_days >= var.min_retention_days && var.copy_retention_days <= var.max_retention_days)
    error_message = "copy_retention_days must lie between min_retention_days and max_retention_days (the copy vault's Vault Lock)."
  }
}

variable "dr_region" {
  description = "Second region for a cross-region copy: the BACKUP_POLICY copies each recovery point to the <vault_name>-cmk vault in this region of the same member account (aws-organization member_backup_dr_region creates it). Also points the policy at the <vault_name>-cmk member vault. Must differ from aws_region and be an allowed region. Null (default) = no cross-region copy."
  type        = string
  default     = null

  validation {
    condition     = var.dr_region == null || (can(regex("^([a-z]{2}|eusc)(-[a-z]+){1,2}-[1-9][0-9]?$", coalesce(var.dr_region, "x"))) && var.dr_region != var.aws_region)
    error_message = "dr_region must be null or an AWS region name that differs from aws_region."
  }
}

variable "dr_copy_retention_days" {
  description = "Days each cross-region copy is kept in the member DR vault."
  type        = number
  default     = 35
  nullable    = false

  validation {
    condition     = var.dr_copy_retention_days >= 1
    error_message = "dr_copy_retention_days must be at least 1."
  }
}

variable "member_vault_name" {
  description = "Name of the member-account vault the BACKUP_POLICY writes to. Null derives it: <vault_name>-cmk with enable_central_copy or dr_region, else vault_name."
  type        = string
  default     = null
}
