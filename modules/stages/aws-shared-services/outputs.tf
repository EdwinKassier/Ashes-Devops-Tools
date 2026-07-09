output "ca_arn" {
  description = "ARN of the ACM Private CA, or null when the Private CA capability is disabled."
  value       = module.private_ca.ca_arn
}

output "secret_arns" {
  description = "Map of secret name to its ARN. Empty when the Secrets Manager baseline is disabled."
  value       = module.secrets_baseline.secret_arns
}
