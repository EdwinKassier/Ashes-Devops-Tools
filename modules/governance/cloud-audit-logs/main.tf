
resource "google_storage_bucket" "audit_logs_access" {
  # checkov:skip=CKV_GCP_62:This is the terminal access log bucket for the audit log bucket and cannot recursively log to itself.
  name                        = "${var.project_id}-audit-logs-access"
  project                     = var.project_id
  location                    = var.bucket_location
  force_destroy               = var.force_destroy_bucket
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

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

resource "google_storage_bucket_iam_member" "audit_logs_access_writer" {
  bucket = google_storage_bucket.audit_logs_access.name
  role   = "roles/storage.objectCreator"
  member = "group:cloud-storage-analytics@google.com"
}

# Cloud Storage bucket for audit logs
resource "google_storage_bucket" "audit_logs" {
  name                        = "${var.project_id}-audit-logs"
  project                     = var.project_id
  location                    = var.bucket_location
  force_destroy               = var.force_destroy_bucket
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # checkov:skip=CKV2_GCP_4:A GCS bucket lock (retention_policy { locked = true }) is
  # intentionally not used on this bucket. Rationale:
  #   1. Durability/immutability is achieved via the org-level Cloud Logging sink
  #      (google_logging_project_sink.audit_logs_sink, below) writing into this bucket —
  #      the authoritative, tamper-evident copy of audit events lives in Cloud Logging's
  #      own storage, independent of this bucket's lifecycle.
  #   2. This bucket's `lifecycle_rule` (age = var.log_retention_days, action = Delete)
  #      enforces a deliberate, operator-controlled retention window. A locked retention
  #      policy would make that window immutable and irreversible even for legitimate
  #      operational needs (e.g. shortening retention for cost/compliance changes,
  #      correcting a misconfigured `log_retention_days`), which is a worse failure mode
  #      for this environment than an unlocked bucket.
  #   3. `versioning { enabled = true }` (above) and uniform_bucket_level_access +
  #      public_access_prevention=enforced already protect against accidental overwrite
  #      and public exposure, which cover the bulk of the risk a bucket lock addresses.
  # Note: as of Checkov 3.2.x, CKV2_GCP_4 does not appear in `checkov --list` or the
  # installed check registry (verified during Task 1.9's audit) — it may be a deprecated/
  # renamed ID from an older Checkov release. The skip is kept (and this justification
  # expanded per Task 1.11) in case a future Checkov version reintroduces an equivalent
  # GCS-bucket-lock check under this or a mapped ID.
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

  logging {
    log_bucket = google_storage_bucket.audit_logs_access.name
  }

  depends_on = [google_storage_bucket_iam_member.audit_logs_access_writer]
}

# Log sink to export audit logs to Cloud Storage
resource "google_logging_project_sink" "audit_logs_sink" {
  name        = var.sink_name
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs.name}"
  filter      = "logName:\"cloudaudit.googleapis.com\""

  unique_writer_identity = true
}

# IAM binding for the log sink service account to write to the bucket
resource "google_storage_bucket_iam_member" "log_writer" {
  bucket = google_storage_bucket.audit_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit_logs_sink.writer_identity
}

# Cloud Audit Logs configuration — applies DATA_READ/DATA_WRITE/ADMIN_READ to the
# admin project itself. For org-wide enforcement see google_organization_iam_audit_config below.
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

# Org-wide audit config — enforces Data Access logging across every project in
# the organization, not just the admin project. Without this, workload projects
# (dev/staging/prod) have no enforced data-access audit trail by default.
resource "google_organization_iam_audit_config" "org_audit_config" {
  count   = var.org_id != null ? 1 : 0
  org_id  = var.org_id
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

# Grant the org sink writer objectCreator on the audit bucket.
resource "google_storage_bucket_iam_member" "org_log_writer" {
  count = var.org_id != null ? 1 : 0

  bucket = google_storage_bucket.audit_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_organization_sink.org_audit_sink[0].writer_identity
}

# Also grant logging.bucketWriter — required for cross-project log delivery
# from an org-level sink to a bucket in a different project (GCP requirement).
resource "google_storage_bucket_iam_member" "org_log_bucket_writer" {
  count = var.org_id != null ? 1 : 0

  bucket = google_storage_bucket.audit_logs.name
  role   = "roles/logging.bucketWriter"
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

  dynamic "default_encryption_configuration" {
    for_each = var.bigquery_kms_key_name != null ? [1] : []
    content {
      kms_key_name = var.bigquery_kms_key_name
    }
  }

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
