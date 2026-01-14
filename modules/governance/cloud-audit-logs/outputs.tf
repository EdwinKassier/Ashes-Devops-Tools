output "audit_config_id" {
  description = "The ID of the created audit config"
  value       = google_project_iam_audit_config.project_audit_logs.id
}

output "configured_service" {
  description = "The service for which audit logging is configured"
  value       = google_project_iam_audit_config.project_audit_logs.service
}

output "storage_bucket_name" {
  description = "The name of the storage bucket where audit logs are exported"
  value       = google_storage_bucket.audit_logs.name
}

output "storage_bucket_url" {
  description = "The URL of the storage bucket where audit logs are exported"
  value       = google_storage_bucket.audit_logs.url
}

output "log_sink_name" {
  description = "The name of the log sink"
  value       = google_logging_project_sink.audit_logs_sink.name
}

output "log_sink_writer_identity" {
  description = "The service account that writes audit logs to the storage bucket"
  value       = google_logging_project_sink.audit_logs_sink.writer_identity
}

output "org_log_sink_name" {
  description = "The name of the organization-level log sink (if created)"
  value       = var.org_id != null ? google_logging_organization_sink.org_audit_sink[0].name : null
}

output "org_log_sink_writer_identity" {
  description = "The service account that writes org-level audit logs to the storage bucket"
  value       = var.org_id != null ? google_logging_organization_sink.org_audit_sink[0].writer_identity : null
}

# =============================================================================
# BIGQUERY LOG ANALYTICS OUTPUTS
# =============================================================================

output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset for audit log analytics (if created)"
  value       = var.org_id != null && var.enable_bigquery_analytics ? google_bigquery_dataset.audit_logs_analytics[0].dataset_id : null
}

output "bigquery_dataset_self_link" {
  description = "The self link of the BigQuery dataset for audit log analytics (if created)"
  value       = var.org_id != null && var.enable_bigquery_analytics ? google_bigquery_dataset.audit_logs_analytics[0].self_link : null
}

output "bigquery_sink_name" {
  description = "The name of the BigQuery log sink (if created)"
  value       = var.org_id != null && var.enable_bigquery_analytics ? google_logging_organization_sink.org_audit_bq_sink[0].name : null
}

output "bigquery_sink_writer_identity" {
  description = "The service account that writes audit logs to BigQuery (if created)"
  value       = var.org_id != null && var.enable_bigquery_analytics ? google_logging_organization_sink.org_audit_bq_sink[0].writer_identity : null
}
