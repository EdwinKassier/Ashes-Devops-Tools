output "trail_arn" {
  description = "The ARN of the organization CloudTrail trail."
  value       = aws_cloudtrail.org.arn
}

output "trail_name" {
  description = "The name of the organization CloudTrail trail."
  value       = aws_cloudtrail.org.name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudTrail CloudWatch Logs group (null when enable_cloudwatch_logs = false)."
  value       = try(aws_cloudwatch_log_group.trail[0].name, null)
}

output "cloudwatch_logs_kms_key_arn" {
  description = "CMK encrypting the CloudWatch Logs group and the CIS alarm topic (module-created or supplied; null when disabled)."
  value       = var.enable_cloudwatch_logs ? local.cw_kms_key_arn : null
}

output "cis_alarm_sns_topic_arn" {
  description = "SNS topic the CIS alarms publish to (module-created or supplied; null when disabled)."
  value       = var.enable_cloudwatch_logs ? local.alarm_topic_arn : null
}

output "cis_alarm_names" {
  description = "Map of CIS alarm key -> CloudWatch alarm name."
  value       = { for k, a in aws_cloudwatch_metric_alarm.cis : k => a.alarm_name }
}

output "cis_metric_filter_patterns" {
  description = "Map of CIS alarm key -> { cis_id, pattern } for every metric filter created."
  value       = local.cis_metric_filters
}
