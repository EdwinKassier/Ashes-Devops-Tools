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

output "access_log_bucket_name" {
  description = "The name of the storage bucket receiving access logs for the audit-log bucket"
  value       = google_storage_bucket.audit_logs_access.name
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

# =============================================================================
# CLOUD LOGGING LOG ANALYTICS OUTPUTS
# =============================================================================

output "log_analytics_bucket_id" {
  description = "Full ID (projects/<p>/locations/<l>/buckets/<b>) of the audit Log Analytics bucket, or null when disabled."
  value       = local.enable_log_analytics ? google_logging_project_bucket_config.audit_analytics[0].id : null
}

output "log_analytics_bucket_location" {
  description = "Location of the audit Log Analytics bucket, or null when disabled."
  value       = local.enable_log_analytics ? local.log_analytics_location : null
}

output "log_analytics_sink_writer_identity" {
  description = "Writer identity of the org sink feeding the Log Analytics bucket, or null when disabled."
  value       = local.enable_log_analytics ? google_logging_organization_sink.org_audit_analytics_sink[0].writer_identity : null
}

output "log_analytics_linked_dataset" {
  description = "Name of the linked BigQuery dataset on the Log Analytics bucket, or null when disabled."
  value       = local.enable_log_analytics && var.enable_log_analytics_linked_dataset ? google_logging_linked_dataset.audit_analytics[0].name : null
}

output "log_retention_days" {
  description = "Days the audit-log bucket keeps objects: the age of its lifecycle Delete rule (and of the locked retention policy when enable_bucket_lock is true)."
  value       = one([for r in google_storage_bucket.audit_logs.lifecycle_rule : one(r.condition).age if one(r.action).type == "Delete"])
}

output "network_log_sink" {
  description = "The org sink that copies firewall, Cloud NAT, load balancer request, Secure Web Proxy and Cloud NGFW threat logs into the audit bucket: name, destination and filter. Null when enable_network_log_export is false or org_id is null."
  value = local.enable_network_log_export ? {
    name        = google_logging_organization_sink.org_network_logs_sink[0].name
    destination = google_logging_organization_sink.org_network_logs_sink[0].destination
    filter      = google_logging_organization_sink.org_network_logs_sink[0].filter
  } : null
}

output "network_log_sink_writer_identity" {
  description = "Writer identity of the network log sink: the org Logging service account it shares with org-audit-sink (a postcondition checks that they match). Null when the sink is not created."
  value       = local.enable_network_log_export ? google_logging_organization_sink.org_network_logs_sink[0].writer_identity : null
}
