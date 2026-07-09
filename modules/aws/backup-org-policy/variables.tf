variable "policy_name" {
  description = "Name of the AWS Organizations BACKUP_POLICY."
  type        = string
  default     = "org-backup-policy"
}

variable "content" {
  description = "Full JSON policy document. When non-empty this overrides the templated default and is used verbatim (must be valid Organizations backup-policy @@assign JSON)."
  type        = string
  default     = ""
}

variable "default_region" {
  description = "AWS region the org backup plan copies recovery points into. Rendered into the templated policy's regions @@assign."
  type        = string
  default     = "eu-west-2"
}

variable "backup_vault_name" {
  description = "Name of the central backup vault the daily rule targets. Rendered into the templated policy."
  type        = string
  default     = "org-backup-vault"
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
