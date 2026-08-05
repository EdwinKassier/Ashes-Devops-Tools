output "topic_arn" {
  description = "ARN of the security-notifications SNS topic."
  value       = module.security_notifications.topic_arn
}

output "rule_names" {
  description = "Names of the detective EventBridge rules."
  value       = module.security_notifications.rule_names
}
