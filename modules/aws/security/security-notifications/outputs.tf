output "topic_arn" {
  description = "ARN of the security-notifications SNS topic, or null when disabled."
  value       = try(aws_sns_topic.this[0].arn, null)
}

output "rule_names" {
  description = "Names of the EventBridge rules that fan detective signals into the topic."
  value       = keys(aws_cloudwatch_event_rule.this)
}
