output "log_archive_bucket_name" {
  description = "Deterministic name of the central log-archive bucket."
  value       = module.aws_security.log_archive_bucket_name
}

output "log_cmk_arn" {
  description = "ARN of the log-archive customer-managed KMS key."
  value       = module.aws_security.log_cmk_arn
}

output "guardduty_detector_ids" {
  description = "Map of Region to GuardDuty detector ID."
  value       = module.aws_security.guardduty_detector_ids
}

output "security_notifications_topic_arn" {
  description = "ARN of the security-notifications SNS topic."
  value       = module.aws_security.security_notifications_topic_arn
}
