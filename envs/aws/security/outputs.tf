# Security cross-root contract. These keys are consumed by downstream aws roots
# via terraform_remote_state. Keep them stable across refactors — renaming a key
# breaks every root that reads it.

locals {
  # The aws-security cross-root contract: ONE non-sensitive object that downstream
  # roots read as .outputs.contract (tfc-admin: tfe_outputs nonsensitive_values
  # .contract). Never put a sensitive value in it: one sensitive attribute moves
  # the whole object into tfe_outputs' sensitive_values. Keys are stable;
  # scripts/check-contracts.sh enforces the read side.
  contract = {
    log_archive_bucket_arn              = module.aws_security.log_archive_bucket_arn
    log_archive_bucket_name             = module.aws_security.log_archive_bucket_name
    log_cmk_arn                         = module.aws_security.log_cmk_arn
    guardduty_detector_ids              = module.aws_security.guardduty_detector_ids
    securityhub_configuration_policy_id = module.aws_security.securityhub_configuration_policy_id
    security_notifications_topic_arn    = module.aws_security.security_notifications_topic_arn
    forensics_account_id                = module.aws_security.forensics_account_id
    break_glass_role_arn                = module.aws_security.break_glass_role_arn
  }
}

output "contract" {
  description = "The aws-security cross-root contract: every key below in one non-sensitive object. Downstream roots read this output only; the individual outputs are deprecated aliases kept until v1.0."
  # Exact shape: a key added to local.contract must be added here too, or the
  # conversion drops it (scripts/check-contracts.sh compares the two key sets).
  type = object({
    log_archive_bucket_arn              = string
    log_archive_bucket_name             = string
    log_cmk_arn                         = string
    guardduty_detector_ids              = map(string)
    securityhub_configuration_policy_id = string
    security_notifications_topic_arn    = string
    forensics_account_id                = string
    break_glass_role_arn                = string
  })
  value = local.contract
}

output "log_archive_bucket_arn" {
  description = "Deprecated: read contract.log_archive_bucket_arn (removed in v1.0). ARN of the central log-archive bucket."
  value       = local.contract.log_archive_bucket_arn
}

output "log_archive_bucket_name" {
  description = "Deprecated: read contract.log_archive_bucket_name (removed in v1.0). Name of the central log-archive bucket. Consumed by aws-workload for flow logs / Config / Session Manager delivery, so a rename here does not silently break downstream logging."
  value       = local.contract.log_archive_bucket_name
}

output "log_cmk_arn" {
  description = "Deprecated: read contract.log_cmk_arn (removed in v1.0). ARN of the log-archive customer-managed KMS key."
  value       = local.contract.log_cmk_arn
}

output "guardduty_detector_ids" {
  description = "Deprecated: read contract.guardduty_detector_ids (removed in v1.0). Map of region to the GuardDuty detector ID created in that region."
  value       = local.contract.guardduty_detector_ids
}

output "securityhub_configuration_policy_id" {
  description = "Deprecated: read contract.securityhub_configuration_policy_id (removed in v1.0). UUID of the baseline Security Hub configuration policy."
  value       = local.contract.securityhub_configuration_policy_id
}

output "security_notifications_topic_arn" {
  description = "Deprecated: read contract.security_notifications_topic_arn (removed in v1.0). ARN of the security-notifications SNS topic (consumed by downstream usage/alarm actions)."
  value       = local.contract.security_notifications_topic_arn
}

output "forensics_account_id" {
  description = "Deprecated: read contract.forensics_account_id (removed in v1.0). 12-digit account ID of the forensics account (echo, part of the cross-root contract)."
  value       = local.contract.forensics_account_id
}

output "break_glass_role_arn" {
  description = "Deprecated: read contract.break_glass_role_arn (removed in v1.0). ARN of the break-glass role the assumption alarm watches (stage-managed when create_break_glass is true, else the external ARN). Use it for the org SCP break-glass exemption."
  value       = local.contract.break_glass_role_arn
}
