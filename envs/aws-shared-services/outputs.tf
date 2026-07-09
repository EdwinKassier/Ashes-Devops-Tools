# Shared-services cross-root contract. These keys are consumed by downstream app
# roots and platform teams. Keep them stable across refactors — renaming a key
# breaks every consumer that reads it.

output "ca_arn" {
  description = "ARN of the org-shared ACM Private CA, or null when the Private CA capability is disabled."
  value       = module.aws_shared_services.ca_arn
}

output "secret_arns" {
  description = "Map of baseline secret name to its ARN. Empty when the Secrets Manager baseline is disabled."
  value       = module.aws_shared_services.secret_arns
}
