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

output "policy_attached_bucket_name" {
  description = "The bucket name, taken from the bucket policy resource so a log producer wired to it (CloudTrail, Config) is created after the policy that lets it write. Use it instead of a module-level depends_on, which defers every data source in the calling module to apply time."
  value       = aws_s3_bucket_policy.this.bucket
}

output "access_log_bucket_name" {
  description = "The bucket that receives the log archive's S3 server access logs: the companion <name>-access-logs bucket, or access_log_bucket when set."
  value       = aws_s3_bucket_logging.this.target_bucket
}

output "retention_days" {
  description = "The planned Object Lock default retention in days (also the lifecycle expiry). It applies to new objects only."
  value       = one(one(aws_s3_bucket_object_lock_configuration.this.rule).default_retention).days
}

output "object_lock_mode" {
  description = "The planned Object Lock default retention mode (COMPLIANCE or GOVERNANCE)."
  value       = one(one(aws_s3_bucket_object_lock_configuration.this.rule).default_retention).mode
}
