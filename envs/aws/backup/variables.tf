# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via backend.hcl / TF_CLI_ARGS_init (kept out of the code so the same root works across orgs and CI)."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from."
  type        = string
  default     = "aws-organization"
}

# -----------------------------------------------------------------------------
# Provider region
# -----------------------------------------------------------------------------

variable "management_account_id" {
  description = "12-digit AWS management (payer) account ID. The default provider sets allowed_account_ids to this, so Terraform fails fast if the resolved credentials are a different account (audit C4). No default: admins must state their own payer account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "Home region for both providers, e.g. eu-west-2. Also the region the org backup plan copies recovery points into."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. eu-west-2."
  }
}

# -----------------------------------------------------------------------------
# Vault (backup account)
# -----------------------------------------------------------------------------

variable "vault_name" {
  description = "Name of the AWS Backup vault created in the backup account. Cross-account naming contract: the management account's org BACKUP_POLICY targets the vault by this name."
  type        = string
  default     = "org-backup-vault"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt recovery points in the vault. Empty string uses the AWS-managed default Backup key."
  type        = string
  default     = ""
}

variable "min_retention_days" {
  description = "Minimum retention (days) enforced on every recovery point stored in the vault."
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

# -----------------------------------------------------------------------------
# IAM role ARNs (operator-supplied)
# -----------------------------------------------------------------------------

variable "backup_role_arn" {
  description = "REQUIRED. ARN of the IAM role AWS Backup assumes to run backup jobs for the resources selected by the org backup plan. Rendered into the org BACKUP_POLICY."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.backup_role_arn))
    error_message = "backup_role_arn must be an account-qualified IAM role ARN."
  }
}

variable "restore_testing_role_arn" {
  description = "REQUIRED. ARN of the IAM role (in the backup account) AWS Backup assumes to perform restore testing jobs."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.restore_testing_role_arn))
    error_message = "restore_testing_role_arn must be an account-qualified IAM role ARN."
  }
}

# -----------------------------------------------------------------------------
# Tagging — provider default_tags (FinOps / governance)
#
# Every resource the aws provider(s) in this root create gets the canonical tag
# set: CostCenter / Environment / Owner (the keys the tag policy enforces and
# cost-governance activates as cost-allocation tags) plus ManagedBy /
# LandingZone / Workspace. default_tags is merged LAST, so it can add keys or
# override any canonical value.
# -----------------------------------------------------------------------------

variable "landing_zone_name" {
  description = "Landing-zone identifier written to the LandingZone tag on every resource."
  type        = string
  default     = "ashes"

  validation {
    condition     = length(trimspace(var.landing_zone_name)) > 0
    error_message = "landing_zone_name must be a non-empty string."
  }
}

variable "cost_center" {
  description = "Value of the CostCenter cost-allocation tag on every resource in this root."
  type        = string
  default     = "platform"

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "cost_center must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "owner" {
  description = "Value of the Owner cost-allocation tag on every resource in this root (team or distribution list)."
  type        = string
  default     = "platform-team"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "default_tags" {
  description = "Extra tags merged into the aws provider default_tags (after the canonical set, so they may override it). Values must be non-empty."
  type        = map(string)
  default     = {}

  validation {
    # An empty-string default tag makes the provider plan a perpetual diff.
    condition     = alltrue([for v in values(var.default_tags) : length(trimspace(v)) > 0])
    error_message = "default_tags values must be non-empty strings."
  }
}

# -----------------------------------------------------------------------------
# Credentials — TFC multi-configuration dynamic credentials
# -----------------------------------------------------------------------------

variable "tfc_aws_dynamic_credentials" {
  description = "Injected by Terraform Cloud when the workspace uses AWS dynamic credentials with multiple configurations: default = the management-account role, aliases[backup] = each member account's tfc-plan / tfc-apply role (TFC_AWS_PROVIDER_AUTH_<alias>, TFC_AWS_PLAN_ROLE_ARN_<alias>, TFC_AWS_APPLY_ROLE_ARN_<alias>). Leave null for local / legacy runs: the member-account providers then assume account_role_arns (OrganizationAccountAccessRole) from management-account credentials."
  type = object({
    default = object({ shared_config_file = string })
    aliases = map(object({ shared_config_file = string }))
  })
  default = null
}
