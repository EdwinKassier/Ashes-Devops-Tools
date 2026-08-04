output "audit_log_bucket" {
  description = "GCS bucket name where audit logs are stored"
  value       = module.audit_logs.storage_bucket_name
}

output "log_sink_writer_identity" {
  description = "Service account identity of the log sink — grant it Storage Object Creator on the bucket"
  value       = module.audit_logs.log_sink_writer_identity
}
