output "alarm_arns" {
  description = "Map of alarm key to the created CloudWatch metric alarm ARN."
  value       = { for k, v in aws_cloudwatch_metric_alarm.this : k => v.arn }
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for alarm actions (created or passed-in); null if none."
  value       = local.sns_topic_arn
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard, or null when enable_dashboard = false."
  value       = var.enable_dashboard ? aws_cloudwatch_dashboard.this[0].dashboard_arn : null
}
