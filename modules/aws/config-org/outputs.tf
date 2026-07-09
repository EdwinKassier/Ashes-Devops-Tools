output "recorder_names" {
  description = "Map of Region to the configuration recorder name deployed in that Region."
  value       = { for region, recorder in aws_config_configuration_recorder.this : region => recorder.name }
}

output "aggregator_arn" {
  description = "ARN of the organization configuration aggregator, or null when recorder_only = true."
  value       = try(aws_config_configuration_aggregator.org[0].arn, null)
}
