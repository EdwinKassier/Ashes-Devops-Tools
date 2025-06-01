terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

# Cloud Storage bucket for audit logs
resource "google_storage_bucket" "audit_logs" {
  name                        = "${var.project_id}-audit-logs"
  project                     = var.project_id
  location                    = var.bucket_location
  force_destroy               = var.force_destroy_bucket
  uniform_bucket_level_access = true

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
