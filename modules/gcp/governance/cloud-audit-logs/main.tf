
resource "google_storage_bucket" "audit_logs_access" {
  # checkov:skip=CKV_GCP_62:This is the terminal access log bucket for the audit log bucket and cannot recursively log to itself.
  name                        = "${var.project_id}-audit-logs-access"
  project                     = var.project_id
  location                    = var.bucket_location
  force_destroy               = var.force_destroy_bucket
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = var.labels

  versioning {
    enabled = true
  }

  # M-4: soft delete keeps deleted/overwritten objects recoverable for
  # soft_delete_retention_days, so a deletion by a compromised identity can be
  # undone within the window (0 disables).
  soft_delete_policy {
    retention_duration_seconds = var.soft_delete_retention_days * 86400
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
  # checkov:skip=CKV_GCP_78:Versioning IS enabled by default (enabled = !var.enable_bucket_lock). It is turned off only when the opt-in WORM retention lock is on, because GCS rejects Object Versioning on a bucket with a retention policy; the locked retention policy plus soft delete is the stronger control in that mode. Checkov cannot evaluate the expression.
  name                        = "${var.project_id}-audit-logs"
  project                     = var.project_id
  location                    = var.bucket_location
  force_destroy               = var.force_destroy_bucket
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = var.labels

  # M-4: Object Versioning keeps overwritten/deleted generations as noncurrent
  # versions. GCS does not allow Object Versioning on a bucket that has a
  # retention policy, so versioning is turned off when the WORM lock below is
  # enabled (the locked retention policy is the stronger control).
  versioning {
    enabled = !var.enable_bucket_lock
  }

  # M-4: soft delete (on by default, 30 days) — deleted objects remain
  # restorable for soft_delete_retention_days even after a delete call. Works
  # with and without the retention lock.
  soft_delete_policy {
    retention_duration_seconds = var.soft_delete_retention_days * 86400
  }

  # Opt-in WORM lock: when enable_bucket_lock = true, a LOCKED retention
  # policy of log_retention_days makes the audit export tamper-proof (undeletable
  # before the window elapses, even by an admin). Default false keeps the
  # operator-correctable behaviour described below. A locked policy is
  # irreversible — enable only for compliance regimes that require it.
  dynamic "retention_policy" {
    for_each = var.enable_bucket_lock ? [1] : []
    content {
      is_locked        = true
      retention_period = var.log_retention_days * 86400
    }
  }

  # checkov:skip=CKV2_GCP_4:A GCS bucket lock (retention_policy { locked = true }) is
  # not used BY DEFAULT on this bucket (it is available opt-in via
  # var.enable_bucket_lock — see the dynamic block above). Rationale for the default:
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

# Grant the org sink writer objectCreator on the audit bucket. For a Cloud
# Storage sink destination this is the only role the writer identity needs:
# https://cloud.google.com/logging/docs/export/configure_export_v2#dest-auth
# (roles/logging.bucketWriter is a Cloud Logging *log-bucket* role and does not
# apply to a Cloud Storage bucket destination.)
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

  dynamic "default_encryption_configuration" {
    for_each = var.bigquery_kms_key_name != null ? [1] : []
    content {
      kms_key_name = var.bigquery_kms_key_name
    }
  }

  labels = merge(var.labels, {
    purpose    = "audit-logs"
    managed-by = "terraform"
  })
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

# =============================================================================
# CLOUD LOGGING LOG ANALYTICS (default on with org_id)
# =============================================================================
# The current Google-recommended way to query audit logs: an org sink routes the
# audit logs into a Cloud Logging log bucket with Log Analytics enabled, and a
# linked BigQuery dataset exposes it read-only to BigQuery (no copy, no second
# retention to manage). Complements the BigQuery-export sink above, which is kept
# so existing datasets are not destroyed on upgrade.
locals {
  enable_log_analytics   = var.org_id != null && var.enable_log_analytics
  log_analytics_location = lower(coalesce(var.log_analytics_location, var.bucket_location))
}

resource "google_logging_project_bucket_config" "audit_analytics" {
  count = local.enable_log_analytics ? 1 : 0

  project          = var.project_id
  location         = local.log_analytics_location
  bucket_id        = var.log_analytics_bucket_id
  description      = "Organization audit logs with Log Analytics (linked BigQuery dataset). Managed by Terraform."
  retention_days   = var.log_analytics_retention_days
  enable_analytics = true
  # Same irreversible opt-in as the GCS WORM lock: a locked log bucket's
  # retention cannot be reduced and the bucket cannot be deleted early.
  locked = var.enable_bucket_lock

  dynamic "cmek_settings" {
    for_each = var.log_analytics_kms_key_name != null ? [1] : []
    content {
      kms_key_name = var.log_analytics_kms_key_name
    }
  }
}

resource "google_logging_organization_sink" "org_audit_analytics_sink" {
  count = local.enable_log_analytics ? 1 : 0

  name             = "org-audit-log-analytics"
  org_id           = var.org_id
  destination      = "logging.googleapis.com/${google_logging_project_bucket_config.audit_analytics[0].id}"
  include_children = true
  filter           = "logName:\"cloudaudit.googleapis.com\""
  description      = "Routes every org audit log into the Log Analytics bucket."
}

# The sink writer may write log entries into this bucket only.
resource "google_project_iam_member" "audit_analytics_writer" {
  count = local.enable_log_analytics ? 1 : 0

  project = var.project_id
  role    = "roles/logging.bucketWriter"
  member  = google_logging_organization_sink.org_audit_analytics_sink[0].writer_identity

  condition {
    title       = "audit_analytics_bucket_only"
    description = "Write only to the audit Log Analytics bucket"
    expression  = "resource.name.endsWith(\"locations/${local.log_analytics_location}/buckets/${var.log_analytics_bucket_id}\")"
  }
}

resource "google_logging_linked_dataset" "audit_analytics" {
  count = local.enable_log_analytics && var.enable_log_analytics_linked_dataset ? 1 : 0

  link_id     = var.log_analytics_link_id
  bucket      = google_logging_project_bucket_config.audit_analytics[0].id
  description = "Read-only BigQuery view of the org audit Log Analytics bucket."
}
