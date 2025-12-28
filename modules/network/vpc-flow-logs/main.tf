/**
 * Copyright 2023 Ashes
 *
 * VPC Flow Logs Export Module - Main Configuration
 * 
 * Creates a log sink for VPC Flow Logs with destination options
 * (BigQuery, Cloud Storage, or Pub/Sub) and supporting resources.
 */

locals {
  sink_filter = var.custom_filter != "" ? var.custom_filter : "resource.type=\"gce_subnetwork\" AND log_id(\"compute.googleapis.com/vpc_flows\")"

  # Determine destination type from destination string
  destination_type = (
    startswith(var.destination, "bigquery.googleapis.com/") ? "bigquery" :
    startswith(var.destination, "storage.googleapis.com/") ? "storage" :
    startswith(var.destination, "pubsub.googleapis.com/") ? "pubsub" :
    var.destination_type
  )
}

# -----------------------------------------------------------------------------
# LOG SINK
# -----------------------------------------------------------------------------

resource "google_logging_project_sink" "flow_logs_sink" {
  project                = var.project_id
  name                   = var.sink_name
  description            = var.description
  destination            = var.destination
  filter                 = local.sink_filter
  unique_writer_identity = true
  disabled               = var.disabled

  dynamic "bigquery_options" {
    for_each = local.destination_type == "bigquery" ? [1] : []
    content {
      use_partitioned_tables = var.bigquery_use_partitioned_tables
    }
  }

  dynamic "exclusions" {
    for_each = var.exclusions
    content {
      name        = exclusions.value.name
      description = exclusions.value.description
      filter      = exclusions.value.filter
      disabled    = try(exclusions.value.disabled, false)
    }
  }
}

# -----------------------------------------------------------------------------
# BIGQUERY DATASET (Optional - when creating destination)
# -----------------------------------------------------------------------------

resource "google_bigquery_dataset" "flow_logs" {
  count = var.create_bigquery_dataset ? 1 : 0

  project                    = var.destination_project_id != "" ? var.destination_project_id : var.project_id
  dataset_id                 = var.bigquery_dataset_id
  friendly_name              = "VPC Flow Logs"
  description                = "Dataset for VPC Flow Logs export"
  location                   = var.bigquery_location
  delete_contents_on_destroy = var.bigquery_delete_contents_on_destroy

  default_table_expiration_ms     = var.bigquery_table_expiration_days != null ? var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000 : null
  default_partition_expiration_ms = var.bigquery_partition_expiration_days != null ? var.bigquery_partition_expiration_days * 24 * 60 * 60 * 1000 : null

  labels = var.labels

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# CLOUD STORAGE BUCKET (Optional - when creating destination)
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "flow_logs" {
  count = var.create_storage_bucket ? 1 : 0

  project                     = var.destination_project_id != "" ? var.destination_project_id : var.project_id
  name                        = var.storage_bucket_name
  location                    = var.storage_location
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = var.storage_force_destroy

  dynamic "lifecycle_rule" {
    for_each = var.storage_retention_days != null ? [1] : []
    content {
      condition {
        age = var.storage_retention_days
      }
      action {
        type = "Delete"
      }
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.storage_archive_days != null ? [1] : []
    content {
      condition {
        age = var.storage_archive_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "ARCHIVE"
      }
    }
  }

  labels = var.labels

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# IAM BINDINGS FOR SINK WRITER
# -----------------------------------------------------------------------------

# BigQuery Dataset IAM
resource "google_bigquery_dataset_iam_member" "sink_writer" {
  count = local.destination_type == "bigquery" ? 1 : 0

  project    = var.destination_project_id != "" ? var.destination_project_id : var.project_id
  dataset_id = var.create_bigquery_dataset ? google_bigquery_dataset.flow_logs[0].dataset_id : var.bigquery_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.flow_logs_sink.writer_identity
}

# Storage Bucket IAM
resource "google_storage_bucket_iam_member" "sink_writer" {
  count = local.destination_type == "storage" ? 1 : 0

  bucket = var.create_storage_bucket ? google_storage_bucket.flow_logs[0].name : var.storage_bucket_name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.flow_logs_sink.writer_identity
}

# Pub/Sub Topic IAM
resource "google_pubsub_topic_iam_member" "sink_writer" {
  count = local.destination_type == "pubsub" ? 1 : 0

  project = var.destination_project_id != "" ? var.destination_project_id : var.project_id
  topic   = var.pubsub_topic_name
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.flow_logs_sink.writer_identity
}
