output "secret_arns" {
  description = "Map of secret name to its ARN. Empty when the module is disabled."
  value       = { for name, s in aws_secretsmanager_secret.this : name => s.arn }
}
