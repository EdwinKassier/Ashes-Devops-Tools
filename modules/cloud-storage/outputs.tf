output "access_logs_bucket_name" {
  description = "Name of the terminal access log bucket (used as log_bucket for other buckets in this module)"
  value       = google_storage_bucket.access_logs.name
}

output "logs_bucket_name" {
  description = "Name of the audit logs bucket (used as a log sink destination)"
  value       = google_storage_bucket.logs.name
}

output "bucket_names" {
  description = "Map of data_buckets key to bucket name for all data buckets in this module"
  value       = { for k, v in google_storage_bucket.data : k => v.name }
}

output "bucket_self_links" {
  description = "Map of data_buckets key to self_link for all data buckets in this module"
  value       = { for k, v in google_storage_bucket.data : k => v.self_link }
}
