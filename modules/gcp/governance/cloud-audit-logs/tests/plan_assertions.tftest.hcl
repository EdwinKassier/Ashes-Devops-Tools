# Plan assertions for the governance/cloud-audit-logs module: verify the audit-log
# bucket is planned with the expected identity, and that the opt-in WORM lock (G8 /
# attaches a locked retention policy only when enable_bucket_lock = true.
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

run "module_labels_applied" {
  command = plan

  variables {
    labels = { owner = "test" }

  }

  assert {
    condition     = google_storage_bucket.audit_logs.labels["owner"] == "test" && google_storage_bucket.audit_logs_access.labels["owner"] == "test"
    error_message = "var.labels must land on the audit-log buckets."
  }
}

# The retention output reads the planned lifecycle rule, and the lock uses the
# same number of days.
run "retention_output_reads_lifecycle" {
  command = plan

  variables {
    log_retention_days = 2190
    enable_bucket_lock = true
  }

  assert {
    condition     = output.log_retention_days == 2190 && tonumber(google_storage_bucket.audit_logs.retention_policy[0].retention_period) == 2190 * 86400
    error_message = "log_retention_days must set the lifecycle Delete age, the output and the locked retention period."
  }
}

# ── CMP-02: network and edge logs into the protected audit store ───────────────

run "network_log_export_off_by_default" {
  command = plan

  variables {
    org_id = "123456789"
  }

  assert {
    condition     = length(google_logging_organization_sink.org_network_logs_sink) == 0
    error_message = "The network log sink must not be planned unless enable_network_log_export = true."
  }

  assert {
    condition     = output.network_log_sink == null
    error_message = "network_log_sink must be null when the export is off."
  }
}

run "network_log_export_needs_org_id" {
  command = plan

  variables {
    enable_network_log_export = true
  }

  assert {
    condition     = length(google_logging_organization_sink.org_network_logs_sink) == 0
    error_message = "The network log sink is an org sink: without org_id nothing must be planned."
  }
}

run "network_log_export_routes_to_audit_bucket" {
  command = plan

  variables {
    org_id                    = "123456789"
    enable_network_log_export = true
  }

  assert {
    condition     = google_logging_organization_sink.org_network_logs_sink[0].destination == "storage.googleapis.com/${var.project_id}-audit-logs"
    error_message = "The network log sink must write to the protected audit bucket (<project>-audit-logs), not to a second store."
  }

  assert {
    condition     = google_logging_organization_sink.org_network_logs_sink[0].include_children == true && google_logging_organization_sink.org_network_logs_sink[0].org_id == "123456789"
    error_message = "The network log sink must be an aggregated org sink (include_children = true)."
  }

  # The sink shares the org Logging service account, which org_log_writer
  # already grants objectCreator: the module adds no IAM binding for it, so
  # turning the export off can never remove the audit export's grant.
  assert {
    condition     = length(google_storage_bucket_iam_member.org_log_writer) == 1
    error_message = "The org audit sink's objectCreator grant (shared by the network log sink) must stay."
  }

  assert {
    condition     = output.network_log_sink.name == "org-network-logs" && output.network_log_sink.destination == "storage.googleapis.com/${var.project_id}-audit-logs"
    error_message = "network_log_sink must report the sink name and destination."
  }
}

# Exact log IDs through log_id() (unencoded), never a logName substring.
run "network_log_filter_uses_exact_log_ids" {
  command = plan

  variables {
    org_id                    = "123456789"
    enable_network_log_export = true
  }

  assert {
    condition = alltrue([
      for id in [
        "compute.googleapis.com/firewall",
        "compute.googleapis.com/nat_flows",
        "requests",
        "loadbalancing.googleapis.com/requests",
        "loadbalancing.googleapis.com/external_regional_requests",
        "networkservices.googleapis.com/gateway_requests",
        "networksecurity.googleapis.com/firewall_threat",
      ] : strcontains(google_logging_organization_sink.org_network_logs_sink[0].filter, "log_id(\"${id}\")")
    ])
    error_message = "The filter must select every network and edge log ID with log_id()."
  }

  assert {
    condition     = !strcontains(google_logging_organization_sink.org_network_logs_sink[0].filter, "logName") && !strcontains(google_logging_organization_sink.org_network_logs_sink[0].filter, "%2F")
    error_message = "The filter must not use logName substrings or URL-encoded IDs."
  }

  assert {
    condition     = strcontains(google_logging_organization_sink.org_network_logs_sink[0].filter, "((log_id(\"requests\") OR log_id(\"loadbalancing.googleapis.com/requests\") OR log_id(\"loadbalancing.googleapis.com/external_regional_requests\")) AND (resource.type=\"http_load_balancer\" OR resource.type=\"internal_http_lb_rule\" OR resource.type=\"http_external_regional_lb_rule\"))")
    error_message = "The request log IDs must be scoped to the load balancer resource types."
  }

  assert {
    condition     = !strcontains(google_logging_organization_sink.org_network_logs_sink[0].filter, "cloudaudit") && !strcontains(google_logging_organization_sink.org_network_logs_sink[0].filter, "vpc_flows")
    error_message = "The filter must not duplicate the audit logs (org-audit-sink) or take the VPC flow logs (exported per environment)."
  }
}

# The postcondition: the network sink must write as the same (shared) service
# account as org-audit-sink, which holds objectCreator on the audit bucket.
run "network_log_sink_shares_audit_writer_identity" {
  command = plan

  variables {
    org_id                    = "123456789"
    enable_network_log_export = true
  }

  override_resource {
    target          = google_logging_organization_sink.org_audit_sink
    override_during = plan
    values = {
      writer_identity = "serviceAccount:service-org-123456789@gcp-sa-logging.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_logging_organization_sink.org_network_logs_sink
    override_during = plan
    values = {
      writer_identity = "serviceAccount:service-org-123456789@gcp-sa-logging.iam.gserviceaccount.com"
    }
  }

  assert {
    condition     = output.network_log_sink_writer_identity == "serviceAccount:service-org-123456789@gcp-sa-logging.iam.gserviceaccount.com"
    error_message = "With the shared org Logging service account the plan must pass."
  }
}

run "network_log_sink_legacy_audit_identity_fails" {
  command = plan

  variables {
    org_id                    = "123456789"
    enable_network_log_export = true
  }

  override_resource {
    target          = google_logging_organization_sink.org_audit_sink
    override_during = plan
    values = {
      writer_identity = "serviceAccount:o123456789-111111@gcp-sa-logging.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_logging_organization_sink.org_network_logs_sink
    override_during = plan
    values = {
      writer_identity = "serviceAccount:service-org-123456789@gcp-sa-logging.iam.gserviceaccount.com"
    }
  }

  expect_failures = [google_logging_organization_sink.org_network_logs_sink]
}

# Legacy audit sink identity after the break-glass grant: the operator sets
# network_log_writer_granted and the differing identities are accepted.
run "network_log_sink_legacy_identity_with_grant_flag_passes" {
  command = plan

  variables {
    org_id                     = "123456789"
    enable_network_log_export  = true
    network_log_writer_granted = true
  }

  override_resource {
    target          = google_logging_organization_sink.org_audit_sink
    override_during = plan
    values = {
      writer_identity = "serviceAccount:o123456789-111111@gcp-sa-logging.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_logging_organization_sink.org_network_logs_sink
    override_during = plan
    values = {
      writer_identity = "serviceAccount:service-org-123456789@gcp-sa-logging.iam.gserviceaccount.com"
    }
  }

  assert {
    condition     = length(google_logging_organization_sink.org_network_logs_sink) == 1
    error_message = "With network_log_writer_granted the sink must plan despite a legacy audit sink identity."
  }
}

# The export adds no IAM binding: the module's IAM resources are the same with
# the export off and on (scripts/check-consistency.sh also fails on any IAM
# resource that binds the network sink's writer identity).
run "iam_bindings_with_export_off" {
  command = plan

  variables {
    org_id = "123456789"
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.org_log_writer) == 1 && length(google_project_iam_member.audit_analytics_writer) == 1 && length(google_bigquery_dataset_iam_member.bq_sink_writer) == 0
    error_message = "Baseline IAM bindings with the export off."
  }
}

run "iam_bindings_unchanged_with_export_on" {
  command = plan

  variables {
    org_id                    = "123456789"
    enable_network_log_export = true
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.org_log_writer) == 1 && length(google_project_iam_member.audit_analytics_writer) == 1 && length(google_bigquery_dataset_iam_member.bq_sink_writer) == 0
    error_message = "Turning the export on must not add or remove an IAM binding."
  }
}
