output "bucket_names" {
  description = "Map of logical key to GCS bucket name"
  value       = module.storage.bucket_names
}

output "logs_bucket" {
  description = "Audit logs sink destination bucket"
  value       = module.storage.logs_bucket_name
}
