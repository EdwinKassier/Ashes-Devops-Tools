output "secret_arns" {
  description = "Map of secret name to ARN created by the module."
  value       = module.secrets_baseline.secret_arns
}
