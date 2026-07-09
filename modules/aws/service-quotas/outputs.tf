output "alarm_names" {
  description = "Names of the AWS/Usage CloudWatch alarms created for each quota-increase request."
  value       = keys(aws_cloudwatch_metric_alarm.usage)
}
