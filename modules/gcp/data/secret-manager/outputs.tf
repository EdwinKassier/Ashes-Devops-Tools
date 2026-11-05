/**
 * Copyright 2023 Ashes
 *
 * Secret Manager Module - Outputs
 */

output "secret_ids" {
  description = "Map of secret name => fully qualified secret id (projects/<p>/secrets/<name>)."
  value       = { for name, secret in google_secret_manager_secret.this : name => secret.id }
}

output "secret_short_ids" {
  description = "Map of secret name => short secret_id."
  value       = { for name, secret in google_secret_manager_secret.this : name => secret.secret_id }
}

output "secret_names" {
  description = "List of created secret names."
  value       = keys(google_secret_manager_secret.this)
}
