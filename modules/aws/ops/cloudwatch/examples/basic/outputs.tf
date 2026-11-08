output "alarm_arns" {
  description = "Map of alarm name to its ARN."
  value       = module.cloudwatch.alarm_arns
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving alarm notifications."
  value       = module.cloudwatch.sns_topic_arn
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard."
  value       = module.cloudwatch.dashboard_arn
}
