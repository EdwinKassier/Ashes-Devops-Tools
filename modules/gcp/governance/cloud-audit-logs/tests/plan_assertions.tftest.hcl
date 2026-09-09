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
