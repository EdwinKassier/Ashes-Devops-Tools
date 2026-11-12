variable "policy_name" {
  description = "Name of the AWS Organizations BACKUP_POLICY."
  type        = string
  default     = "org-backup-policy"
}

variable "content" {
  description = "Full JSON policy document. When non-empty this overrides the generated default and is used verbatim (must be valid Organizations backup-policy @@assign JSON)."
  type        = string
  default     = ""
}

variable "default_region" {
  description = "AWS region the org backup plan writes recovery points to (single region). Rendered into the policy's regions @@assign. Copies to other regions or accounts come from copy_actions."
  type        = string
  default     = "eu-west-2"
}

variable "backup_vault_name" {
  description = "Name of the vault the daily rule writes to in each member account (the policy runs its jobs in the member account)."
  type        = string
  default     = "org-backup-vault"
}

variable "retention_days" {
  description = "Days the daily rule keeps each recovery point in the member vault (lifecycle delete_after_days)."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days must be at least 1."
  }
}

variable "copy_actions" {
  description = "Copy each daily recovery point to these vaults (rules.daily.copy_actions). destination_vault_arn may use the Organizations backup policy variable $account for the member account. Cross-account copy needs org-wide cross-account backup and a customer managed key on the source vault. delete_after_days must fit the destination vault's Vault Lock min/max retention, or the copy job fails. Empty (default) = no copy."
  type = list(object({
    destination_vault_arn = string
    delete_after_days     = number
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for c in var.copy_actions : can(regex("^arn:aws[a-z-]*:backup:[a-z0-9-]+:([0-9]{12}|[$]account):backup-vault:[A-Za-z0-9_-]{2,50}$", c.destination_vault_arn)) && c.delete_after_days >= 1])
    error_message = "copy_actions entries need a backup-vault ARN (arn:PARTITION:backup:REGION:ACCOUNT:backup-vault:NAME, ACCOUNT a 12-digit ID or $account) and delete_after_days >= 1."
  }

  validation {
    condition     = length(distinct([for c in var.copy_actions : c.destination_vault_arn])) == length(var.copy_actions)
    error_message = "copy_actions destination_vault_arn values must be unique (the policy keys copy actions by destination)."
  }
}

variable "backup_role_arn" {
  description = "ARN of the IAM role AWS Backup assumes to run backup jobs for the selected resources."
  type        = string
}

variable "target_ou_id" {
  description = "ID of the OU the policy is attached to (typically the Workloads OU)."
  type        = string

  validation {
    # Organizations policy targets are either an OU (ou-...) or the org root
    # (r-...); reject anything that is not one of those id shapes.
    condition     = can(regex("^(r|ou)-[a-z0-9-]+$", var.target_ou_id))
    error_message = "target_ou_id must be an Organizations OU id (ou-xxxx-yyyy) or root id (r-xxxx)."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
