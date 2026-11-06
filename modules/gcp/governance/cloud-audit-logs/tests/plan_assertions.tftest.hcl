# Plan assertions for the governance/cloud-audit-logs module: verify the audit-log
# bucket is planned with the expected identity, and that the opt-in WORM lock (G8 /
# audit M2) attaches a locked retention policy only when enable_bucket_lock = true.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
}

run "audit_bucket_identity" {
  command = plan

  assert {
    condition     = google_storage_bucket.audit_logs.name == "${var.project_id}-audit-logs"
    error_message = "Audit-log bucket must be named <project>-audit-logs."
  }

  assert {
    condition     = google_storage_bucket.audit_logs.project == var.project_id
    error_message = "Audit-log bucket must be created in the caller-supplied project."
  }
}

run "bucket_lock_off_by_default" {
  command = plan

  assert {
    condition     = length(google_storage_bucket.audit_logs.retention_policy) == 0
    error_message = "No retention policy must be planned when enable_bucket_lock is false (default)."
  }
}

run "bucket_lock_locks_retention_when_enabled" {
  command = plan

  variables {
    enable_bucket_lock = true
  }

  assert {
    condition     = length(google_storage_bucket.audit_logs.retention_policy) == 1
    error_message = "A retention policy must be planned when enable_bucket_lock = true."
  }

  assert {
    condition     = google_storage_bucket.audit_logs.retention_policy[0].is_locked == true
    error_message = "The opt-in retention policy must be locked (WORM)."
  }
}

# ── M-4: versioning + soft delete on by default ────────────────────────────────

run "versioning_and_soft_delete_on_by_default" {
  command = plan

  assert {
    condition     = google_storage_bucket.audit_logs.versioning[0].enabled == true
    error_message = "Object Versioning must be enabled on the audit bucket by default."
  }

  assert {
    condition     = google_storage_bucket.audit_logs.soft_delete_policy[0].retention_duration_seconds == 30 * 86400
    error_message = "The audit bucket must have a 30-day soft-delete policy by default."
  }

  assert {
    condition     = google_storage_bucket.audit_logs_access.soft_delete_policy[0].retention_duration_seconds == 30 * 86400
    error_message = "The access-log bucket must have a 30-day soft-delete policy by default."
  }
}

run "bucket_lock_disables_versioning" {
  command = plan

  variables {
    enable_bucket_lock = true
  }

  # GCS rejects Object Versioning on a bucket with a retention policy.
  assert {
    condition     = google_storage_bucket.audit_logs.versioning[0].enabled == false
    error_message = "Versioning must be off when the retention lock is on (GCS forbids both)."
  }

  assert {
    condition     = google_storage_bucket.audit_logs.soft_delete_policy[0].retention_duration_seconds == 30 * 86400
    error_message = "Soft delete must stay on alongside the retention lock."
  }
}

# Log Analytics: on by default with org_id — an analytics-enabled log bucket, an
# org sink into it, a bucket-scoped writer grant and a linked BigQuery dataset.
run "log_analytics_on_by_default_with_org" {
  command = plan

  variables {
    org_id          = "123456789"
    bucket_location = "europe-west1"
  }

  assert {
    condition     = google_logging_project_bucket_config.audit_analytics[0].enable_analytics == true && google_logging_project_bucket_config.audit_analytics[0].location == "europe-west1"
    error_message = "The audit Log Analytics bucket must have analytics enabled in the bucket location."
  }

  assert {
    condition     = google_logging_project_bucket_config.audit_analytics[0].locked == false
    error_message = "The Log Analytics bucket must stay unlocked unless enable_bucket_lock is set."
  }

  assert {
    condition     = google_logging_organization_sink.org_audit_analytics_sink[0].include_children == true && strcontains(google_logging_organization_sink.org_audit_analytics_sink[0].filter, "cloudaudit.googleapis.com")
    error_message = "An org sink must route every child's audit logs into the analytics bucket."
  }

  assert {
    condition     = google_project_iam_member.audit_analytics_writer[0].role == "roles/logging.bucketWriter" && strcontains(google_project_iam_member.audit_analytics_writer[0].condition[0].expression, "buckets/org-audit-analytics")
    error_message = "The sink writer must get bucketWriter scoped to the analytics bucket only."
  }

  assert {
    condition     = google_logging_linked_dataset.audit_analytics[0].link_id == "org_audit_analytics"
    error_message = "A linked BigQuery dataset must be created on the analytics bucket."
  }
}

run "log_analytics_needs_org_and_can_be_disabled" {
  command = plan

  variables {
    org_id               = "123456789"
    enable_log_analytics = false
  }

  assert {
    condition     = length(google_logging_project_bucket_config.audit_analytics) == 0 && length(google_logging_linked_dataset.audit_analytics) == 0 && output.log_analytics_bucket_id == null
    error_message = "enable_log_analytics = false must create no Log Analytics resources."
  }
}

run "log_analytics_locked_with_bucket_lock_and_cmek" {
  command = plan

  variables {
    org_id                     = "123456789"
    enable_bucket_lock         = true
    log_analytics_kms_key_name = "projects/p/locations/us/keyRings/r/cryptoKeys/k"
  }

  assert {
    condition     = google_logging_project_bucket_config.audit_analytics[0].locked == true && google_logging_project_bucket_config.audit_analytics[0].location == "us"
    error_message = "enable_bucket_lock must also lock the Log Analytics bucket; the location defaults to the lower-cased bucket_location."
  }

  assert {
    condition     = google_logging_project_bucket_config.audit_analytics[0].cmek_settings[0].kms_key_name == "projects/p/locations/us/keyRings/r/cryptoKeys/k"
    error_message = "log_analytics_kms_key_name must set the bucket CMEK."
  }
}
