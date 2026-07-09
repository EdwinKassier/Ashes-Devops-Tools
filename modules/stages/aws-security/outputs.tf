output "log_archive_bucket_arn" {
  description = "ARN of the central log-archive bucket."
  value       = module.log_archive_bucket.bucket_arn
}

output "log_archive_bucket_name" {
  description = "Deterministic name of the central log-archive bucket (the cross-root naming contract)."
  value       = module.log_archive_bucket.bucket_name
}

output "log_cmk_arn" {
  description = "ARN of the log-archive customer-managed KMS key."
  value       = module.log_cmk.key_arn
}

output "forensics_cmk_arn" {
  description = "ARN of the forensics customer-managed KMS key."
  value       = module.forensics_cmk.key_arn
}

output "sectool_cmk_arn" {
  description = "ARN of the security-tooling customer-managed KMS key that encrypts the SNS topic and SSM session data (created in the security-tooling account so those local services can use it)."
  value       = module.sectool_cmk.key_arn
}

output "guardduty_detector_ids" {
  description = "Map of Region to the GuardDuty detector ID created in that Region."
  value       = module.guardduty.detector_ids
}

output "securityhub_configuration_policy_id" {
  description = "UUID of the baseline Security Hub configuration policy."
  value       = module.securityhub.configuration_policy_id
}

output "security_notifications_topic_arn" {
  description = "ARN of the security-notifications SNS topic (consumed by downstream usage/alarm actions)."
  value       = module.security_notifications.topic_arn
}

output "forensics_account_id" {
  description = "12-digit account ID of the forensics account (echo of the input, part of the cross-root contract)."
  value       = var.forensics_account_id
}
