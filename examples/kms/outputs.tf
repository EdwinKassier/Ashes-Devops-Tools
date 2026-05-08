output "app_key_id" {
  description = "KMS key ID for application data encryption"
  value       = module.kms.key_ids["app-data-key"]
}

output "log_key_id" {
  description = "KMS key ID for log encryption"
  value       = module.kms.key_ids["log-encryption-key"]
}
