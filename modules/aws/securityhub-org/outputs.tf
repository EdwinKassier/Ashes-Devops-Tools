output "configuration_policy_id" {
  description = "The UUID of the baseline Security Hub configuration policy."
  value       = aws_securityhub_configuration_policy.baseline.id
}

output "finding_aggregator_arn" {
  description = "The ARN of the Security Hub finding aggregator (ALL_REGIONS)."
  value       = aws_securityhub_finding_aggregator.this.arn
}
