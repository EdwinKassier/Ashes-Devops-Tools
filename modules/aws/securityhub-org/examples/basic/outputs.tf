output "configuration_policy_id" {
  description = "The UUID of the baseline Security Hub configuration policy."
  value       = module.securityhub_org.configuration_policy_id
}

output "finding_aggregator_arn" {
  description = "The ARN of the Security Hub finding aggregator."
  value       = module.securityhub_org.finding_aggregator_arn
}
