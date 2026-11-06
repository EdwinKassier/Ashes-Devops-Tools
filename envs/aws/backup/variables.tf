# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via backend.hcl / TF_CLI_ARGS_init (kept out of the code so the same root works across orgs and CI). Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from."
  type        = string
  default     = "aws-organization"
}

variable "organization_contract" {
  description = "aws-organization stage contract (FAST-style override): account_ids (account key => 12-digit ID), account_role_arns (account key => cross-account role ARN), ou_ids (OU name => OU ID). When set, the aws-organization remote state is NOT read. Null = aws.contracts.organization from config/landing-zone.yaml, else read from the organization_workspace_name workspace's remote state."
  type = object({
    account_ids       = map(string)
    account_role_arns = map(string)
    ou_ids            = map(string)
  })
  default = null

  validation {
    condition     = var.organization_contract == null || alltrue([for id in values(try(var.organization_contract.account_ids, {})) : can(regex("^[0-9]{12}$", id))])
    error_message = "organization_contract.account_ids values must be 12-digit AWS account IDs."
  }
}

# -----------------------------------------------------------------------------
# Provider region
# -----------------------------------------------------------------------------

variable "management_account_id" {
  description = "12-digit AWS management (payer) account ID. The default provider sets allowed_account_ids to this, so Terraform fails fast if the resolved credentials are a different account (audit C4). Null = aws.management_account_id from config/landing-zone.yaml (quote it there); no built-in default."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[0-9]{12}$", coalesce(var.management_account_id, local.cfg.management_account_id, "!unset")))
    error_message = "management_account_id is unset or invalid: set var.management_account_id or aws.management_account_id in config/landing-zone.yaml (quoted) to the 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "Home region for both providers, e.g. eu-west-2. Also the region the org backup plan copies recovery points into. Null = org.regions.aws from config/landing-zone.yaml, else eu-west-2."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")))
    error_message = "aws_region (or org.regions.aws in config/landing-zone.yaml) must be a valid AWS region name, e.g. eu-west-2."
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
  description = "ARN of the IAM role AWS Backup assumes in EACH member account under the Workloads OU to run the org backup plan, rendered into the org BACKUP_POLICY (may use $account). Null (default): the stage deploys backup_role_name to every Workloads-OU account via a service-managed StackSet and renders arn:aws:iam::$account:role/<backup_role_name>."
  type        = string
  default     = null

  validation {
    condition     = var.backup_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|[$]account):role/.+$", coalesce(var.backup_role_arn, "x")))
    error_message = "backup_role_arn must be null or an IAM role ARN whose account is a 12-digit ID or $account."
  }
}

variable "backup_role_name" {
  description = "Name of the member-account AWS Backup service role the StackSet deploys when backup_role_arn is null."
  type        = string
  default     = "aws-backup-org-role"
}

variable "restore_testing_role_arn" {
  description = "ARN of an existing IAM role in the BACKUP account that AWS Backup assumes for restore testing. Null (default) creates aws-backup-restore-testing there (backup.amazonaws.com trust, AWSBackupServiceRolePolicyForRestores)."
  type        = string
  default     = null

  validation {
    condition     = var.restore_testing_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.restore_testing_role_arn, "x")))
    error_message = "restore_testing_role_arn must be null or an account-qualified IAM role ARN."
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
  description = "Landing-zone identifier written to the LandingZone tag on every resource. Null = org.name from config/landing-zone.yaml (the single source shared by every AWS root). The upstream placeholders \"ashes\" and \"my-org\" are rejected."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "!unset")))
    error_message = "landing_zone_name is unset or invalid: set var.landing_zone_name or org.name in config/landing-zone.yaml. It must be 2-31 chars: a lowercase letter, then lowercase letters, digits or hyphens."
  }

  validation {
    condition     = !contains(["ashes", "my-org"], lower(coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "!unset")))
    error_message = "landing_zone_name is still an upstream placeholder (ashes / my-org). Set your own landing-zone identifier."
  }
}

variable "cost_center" {
  description = "Value of the CostCenter cost-allocation tag on every resource in this root. Null = org.cost_center from config/landing-zone.yaml, else \"platform\"."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform"))) > 0
    error_message = "cost_center must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "owner" {
  description = "Value of the Owner cost-allocation tag on every resource in this root (team or distribution list). Null = org.owner from config/landing-zone.yaml, else \"platform-team\"."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team"))) > 0
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
