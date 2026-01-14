
# Cloud Storage bucket for audit logs
resource "google_storage_bucket" "audit_logs" {
  name                        = "${var.project_id}-audit-logs"
  project                     = var.project_id
  location                    = var.bucket_location
  force_destroy               = var.force_destroy_bucket
  uniform_bucket_level_access = true

  # checkov:skip=CKV2_GCP_4:Bucket lock prevents deletion and is too restrictive for this environment
  dynamic "encryption" {
    for_each = var.kms_key_name != null ? [1] : []
    content {
      default_kms_key_name = var.kms_key_name
    }
  }

  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
}

# Log sink to export audit logs to Cloud Storage
resource "google_logging_project_sink" "audit_logs_sink" {
  name        = "audit-logs-sink"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs.name}"
  filter      = "resource.type=project AND protoPayload.@type=type.googleapis.com/google.cloud.audit.AuditLog"

  unique_writer_identity = true
}

# IAM binding for the log sink service account to write to the bucket
resource "google_storage_bucket_iam_binding" "log_writer" {
  bucket = google_storage_bucket.audit_logs.name
  role   = "roles/storage.objectCreator"
  members = [
    google_logging_project_sink.audit_logs_sink.writer_identity,
  ]
}

# Cloud Audit Logs configuration
resource "google_project_iam_audit_config" "project_audit_logs" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Organization-level log sink (captures audit logs from all projects)
# This is a best practice to ensure centralized audit logging across the org
resource "google_logging_organization_sink" "org_audit_sink" {
  count = var.org_id != null ? 1 : 0

  name             = "org-audit-sink"
  org_id           = var.org_id
  destination      = "storage.googleapis.com/${google_storage_bucket.audit_logs.name}"
  include_children = true

  # Filter for all audit logs
  filter = "logName:cloudaudit.googleapis.com"
}

# Grant the org sink writer access to the bucket
resource "google_storage_bucket_iam_member" "org_log_writer" {
  count = var.org_id != null ? 1 : 0

  bucket = google_storage_bucket.audit_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_organization_sink.org_audit_sink[0].writer_identity
}

# =============================================================================
# BIGQUERY LOG ANALYTICS (Optional)
# =============================================================================

# BigQuery dataset for audit log analytics
resource "google_bigquery_dataset" "audit_logs_analytics" {
  count = var.org_id != null && var.enable_bigquery_analytics ? 1 : 0

  dataset_id    = "org_audit_logs_analytics"
  friendly_name = "Organization Audit Logs Analytics"
  description   = "Dataset for querying and analyzing organization-wide audit logs"
  location      = var.bigquery_location
  project       = var.project_id

  # Partition expiration for cost management
  default_partition_expiration_ms = var.bigquery_retention_days * 24 * 60 * 60 * 1000

  labels = {
    purpose    = "audit-logs"
    managed-by = "terraform"
  }
}

# Organization-level log sink to BigQuery for analytics
resource "google_logging_organization_sink" "org_audit_bq_sink" {
  count = var.org_id != null && var.enable_bigquery_analytics ? 1 : 0

  name             = "org-audit-logs-bq-analytics"
  org_id           = var.org_id
  destination      = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.audit_logs_analytics[0].dataset_id}"
  include_children = true

  # Filter for Admin Activity and Policy logs (most useful for analytics)
  # Data Access logs can be very high volume; add them if needed
  filter = <<-EOF
    logName:("cloudaudit.googleapis.com/activity" OR 
             "cloudaudit.googleapis.com/policy")
  EOF

  # Use partitioned tables for better query performance and cost optimization
  bigquery_options {
    use_partitioned_tables = true
  }
}

# Grant the BigQuery sink write access to the dataset
resource "google_bigquery_dataset_iam_member" "bq_sink_writer" {
  count = var.org_id != null && var.enable_bigquery_analytics ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.audit_logs_analytics[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_organization_sink.org_audit_bq_sink[0].writer_identity
}
