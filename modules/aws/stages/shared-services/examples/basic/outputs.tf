output "ca_arn" {
  description = "ARN of the ACM Private CA, or null when disabled."
  value       = module.aws_shared_services.ca_arn
}

output "secret_arns" {
  description = "Map of secret name to its ARN."
  value       = module.aws_shared_services.secret_arns
}
