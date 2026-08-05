output "data_lake_arn" {
  description = "ARN of the Security Lake data lake."
  value       = module.securitylake.data_lake_arn
}

output "log_source_names" {
  description = "Names of the AWS-native log sources ingested into Security Lake."
  value       = module.securitylake.log_source_names
}
