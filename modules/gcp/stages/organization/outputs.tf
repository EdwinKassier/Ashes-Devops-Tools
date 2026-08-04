output "folders" {
  description = "Map of created folders"
  value       = module.organization.folders
}

output "organization_id" {
  description = "Organization ID"
  value       = module.organization.organization_id
}

output "tag_keys" {
  description = "Tag keys available to downstream consumers"
  value       = module.tags.tag_keys
}

output "tag_value_ids" {
  description = "Tag values available to downstream consumers"
  value       = module.tags.tag_values
}

output "audit_logs_bucket_name" {
  description = "Name of the Cloud Storage bucket receiving audit logs"
  value       = module.audit_logs.storage_bucket_name
}

output "billing_export_dataset_id" {
  description = "BigQuery dataset ID for Cloud Billing export data"
  value       = google_bigquery_dataset.billing_export.dataset_id
}

output "scc_pubsub_topic_id" {
  description = "Pub/Sub topic ID receiving Security Command Center findings notifications"
  value       = module.scc_notifications.topic_id
}

output "cmek_key_names" {
  description = "Map of KMS key short names to fully qualified key resource IDs created by the CMEK module"
  value       = module.cmek.key_names
}
