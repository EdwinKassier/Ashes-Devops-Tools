# Access log bucket for storage buckets.
resource "google_storage_bucket" "access_logs" {
  # checkov:skip=CKV_GCP_62:This is the terminal access log bucket for the module and cannot recursively log to itself.
  name                        = "${var.project_id}-bucket-access-logs"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning {
    enabled = true
  }
  encryption {
    default_kms_key_name = var.kms_key_name
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
  member = "group:cloud-storage-analytics@google.com"
}

# Logs bucket for audit logs
resource "google_storage_bucket" "logs" {
  name                        = "${var.project_id}-logs"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning {
    enabled = true
  }
  encryption {
    default_kms_key_name = var.kms_key_name
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
  member = "group:cloud-storage-analytics@google.com"
}

# Generic data buckets — driven by var.data_buckets
resource "google_storage_bucket" "data" {
  for_each = var.data_buckets

  name                        = "${var.project_id}-${each.value.name_suffix}"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning {
    enabled = true
  }
  logging {
    log_bucket = google_storage_bucket.logs.name
  }
  encryption {
    default_kms_key_name = var.kms_key_name
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
