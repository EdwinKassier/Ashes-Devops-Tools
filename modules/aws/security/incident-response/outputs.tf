output "isolation_lambda_arn" {
  description = "ARN of the isolation Lambda, or null when incident response is disabled."
  value       = try(aws_lambda_function.isolate[0].arn, null)
}

output "guardduty_rule_arn" {
  description = "ARN of the EventBridge rule matching high-severity GuardDuty findings, or null when disabled."
  value       = try(aws_cloudwatch_event_rule.guardduty_high[0].arn, null)
}

output "forensics_role_arn" {
  description = "ARN of the forensics snapshot-sharing role, or null when disabled."
  value       = try(aws_iam_role.forensics_snapshot[0].arn, null)
}

output "quarantine_security_group_id" {
  description = "ID of the deny-all quarantine security group, or null when incident response is disabled or quarantine_vpc_id is unset."
  value       = try(aws_security_group.quarantine[0].id, null)
}
