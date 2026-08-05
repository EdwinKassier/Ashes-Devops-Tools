output "isolation_lambda_arn" {
  description = "ARN of the isolation Lambda."
  value       = module.incident_response.isolation_lambda_arn
}

output "forensics_role_arn" {
  description = "ARN of the forensics snapshot-sharing role."
  value       = module.incident_response.forensics_role_arn
}
