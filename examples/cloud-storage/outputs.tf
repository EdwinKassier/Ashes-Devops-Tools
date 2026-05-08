output "raw_bucket_name" {
  description = "Name of the raw ingest bucket"
  value       = module.storage.bucket_names["raw-ingest"]
}

output "logs_bucket_name" {
  description = "Audit logs bucket name (use as a logging sink destination)"
  value       = module.storage.logs_bucket_name
}
