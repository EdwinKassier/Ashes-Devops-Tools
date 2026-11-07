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

output "break_glass_role_arn" {
  description = "ARN of the break-glass role the assumption alarm watches: the stage-managed role when create_break_glass is true, else the externally-managed ARN passed in. Use it to set the org SCP break-glass exemptions. Empty when neither is set."
  value       = local.effective_break_glass_role_arn
}

output "cloudtrail_log_group_name" {
  description = "CloudWatch Logs group the org trail delivers into: the delegated-admin trail's (security-tooling account) when enable_cloudtrail_delegated_admin is true, else the management account's; null when enable_cloudwatch_logs = false."
  value       = try(module.cloudtrail_delegated_admin[0].cloudwatch_log_group_name, module.cloudtrail[0].cloudwatch_log_group_name, null)
}

output "cis_alarm_sns_topic_arn" {
  description = "SNS topic the CIS section-4 alarms publish to: in security tooling when enable_cloudtrail_delegated_admin is true, else in the management account; null when enable_cloudwatch_logs = false."
  value       = try(module.cloudtrail_delegated_admin[0].cis_alarm_sns_topic_arn, module.cloudtrail[0].cis_alarm_sns_topic_arn, null)
}

output "delegated_admin_trail_arn" {
  description = "ARN of the organization trail managed by the CloudTrail delegated administrator (owned by the management account), or null when enable_cloudtrail_delegated_admin is false."
  value       = try(module.cloudtrail_delegated_admin[0].trail_arn, null)
}

output "key_admin_arns" {
  description = "Key administrator per CMK (log_archive / forensics / security_tooling): key_admin_arn, or each key account's key_admin_role_name role when null."
  value       = local.key_admin_arns
}

output "config_role_arn" {
  description = "IAM role the security-tooling Config recorders use (the AWSServiceRoleForConfig SLR unless config_role_arn was set)."
  value       = module.config.config_role_arn
}

output "config_aggregator_role_arn" {
  description = "IAM role the Config organization aggregator assumes (created by the stage unless aggregator_role_arn was set)."
  value       = module.config.aggregator_role_arn
}
