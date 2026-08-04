locals {
  # GCS service agent that writes access logs and storage logs on behalf of GCS buckets.
  # This is a Google-managed group and does not change between projects or regions.
  gcs_log_writer = "group:cloud-storage-analytics@google.com"
}

# Access log bucket for storage buckets.
resource "google_storage_bucket" "access_logs" {
  # checkov:skip=CKV_GCP_62:This is the terminal access log bucket for the module and cannot recursively log to itself.
  name                        = "${var.project_id}-bucket-access-logs"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = var.labels
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

resource "google_storage_bucket_iam_member" "access_log_writer" {
  bucket = google_storage_bucket.access_logs.name
  role   = "roles/storage.objectCreator"
  member = local.gcs_log_writer
}

# Logs bucket for audit logs
resource "google_storage_bucket" "logs" {
  name                        = "${var.project_id}-logs"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = var.labels
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
  logging {
    log_bucket = google_storage_bucket.access_logs.name
  }
  depends_on = [google_storage_bucket_iam_member.access_log_writer]
}

# IAM member for log writer
resource "google_storage_bucket_iam_member" "log_writer" {
  bucket = google_storage_bucket.logs.name
  role   = "roles/storage.objectCreator"
  member = local.gcs_log_writer
}

# Generic data buckets — driven by var.data_buckets
resource "google_storage_bucket" "data" {
  for_each = var.data_buckets

  name                        = "${var.project_id}-${each.value.name_suffix}"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = each.value.force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = var.labels
  versioning {
    enabled = true
  }
  logging {
    log_bucket = google_storage_bucket.logs.name
  }
  dynamic "encryption" {
    for_each = var.kms_key_name != null ? [1] : []
    content {
      default_kms_key_name = var.kms_key_name
    }
  }

  # H-1: Apply soft-delete retention from per-bucket config.
  # Set soft_delete_retention_seconds = 0 to disable soft-delete (useful in dev/test).
  soft_delete_policy {
    retention_duration_seconds = each.value.soft_delete_retention_seconds
  }

  # M-7: Optional data retention lifecycle expiry.
  # When retention_days is set, objects are automatically deleted after that many days.
  dynamic "lifecycle_rule" {
    for_each = each.value.retention_days != null ? [1] : []
    content {
      condition {
        age = each.value.retention_days
      }
      action {
        type = "Delete"
      }
    }
  }

  depends_on = [google_storage_bucket_iam_member.log_writer]
}

# IAM members for private read access to all data buckets
resource "google_storage_bucket_iam_member" "private" {
  for_each = {
    for binding in flatten([
      for key, bucket in google_storage_bucket.data : [
        for member in var.allowed_members : {
          key    = "${key}-${substr(md5(member), 0, 12)}"
          bucket = bucket.name
          member = member
        }
      ]
    ]) : binding.key => binding
  }

  bucket = each.value.bucket
  role   = "roles/storage.objectViewer"
  member = each.value.member
}
