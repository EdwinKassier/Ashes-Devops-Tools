output "bucket_id" {
  description = "The name (ID) of the log-archive bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the log-archive bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_name" {
  description = "The deterministic bucket name (equals var.log_archive_bucket_name); the cross-root naming contract the B3 SCP references."
  value       = var.log_archive_bucket_name
}
