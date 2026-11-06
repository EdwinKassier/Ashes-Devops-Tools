output "recorder_names" {
  description = "Map of Region to the configuration recorder name deployed in that Region."
  value       = { for region, recorder in aws_config_configuration_recorder.this : region => recorder.name }
}

output "aggregator_arn" {
  description = "ARN of the organization configuration aggregator, or null when recorder_only = true."
  value       = try(aws_config_configuration_aggregator.org[0].arn, null)
}

output "config_role_arn" {
  description = "ARN of the IAM role the recorders use: the explicit config_role_arn or the AWSServiceRoleForConfig service-linked role."
  value       = local.config_role_arn
}

output "aggregator_role_arn" {
  description = "ARN of the role the organization aggregator assumes (created here when aggregator_role_arn was null/empty), or null when recorder_only = true."
  value       = var.recorder_only ? null : local.aggregator_role_arn
}
