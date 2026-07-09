# Security cross-root contract. These keys are consumed by downstream aws roots
# via terraform_remote_state. Keep them stable across refactors — renaming a key
# breaks every root that reads it.

output "log_archive_bucket_arn" {
  description = "ARN of the central log-archive bucket."
  value       = module.aws_security.log_archive_bucket_arn
}

output "log_cmk_arn" {
  description = "ARN of the log-archive customer-managed KMS key."
  value       = module.aws_security.log_cmk_arn
}

output "guardduty_detector_ids" {
  description = "Map of region to the GuardDuty detector ID created in that region."
  value       = module.aws_security.guardduty_detector_ids
}

output "securityhub_configuration_policy_id" {
  description = "UUID of the baseline Security Hub configuration policy."
  value       = module.aws_security.securityhub_configuration_policy_id
}

output "security_notifications_topic_arn" {
  description = "ARN of the security-notifications SNS topic (consumed by downstream usage/alarm actions)."
  value       = module.aws_security.security_notifications_topic_arn
}

output "forensics_account_id" {
  description = "12-digit account ID of the forensics account (echo, part of the cross-root contract)."
  value       = module.aws_security.forensics_account_id
}
