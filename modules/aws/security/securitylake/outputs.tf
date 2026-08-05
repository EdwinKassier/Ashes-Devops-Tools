output "data_lake_arn" {
  description = "ARN of the Security Lake data lake, or null when Security Lake is disabled."
  value       = try(aws_securitylake_data_lake.this[0].arn, null)
}

output "log_source_names" {
  description = "Names of the AWS-native log sources ingested into Security Lake."
  value       = keys(aws_securitylake_aws_log_source.this)
}
