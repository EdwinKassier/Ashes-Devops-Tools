output "bucket_arn" {
  description = "The ARN of the log-archive bucket created by the module."
  value       = module.log_archive_bucket.bucket_arn
}

output "bucket_name" {
  description = "The deterministic bucket name."
  value       = module.log_archive_bucket.bucket_name
}
