output "recorder_names" {
  description = "Map of Region to configuration recorder name."
  value       = module.config_org.recorder_names
}

output "aggregator_arn" {
  description = "ARN of the organization configuration aggregator."
  value       = module.config_org.aggregator_arn
}
