# Logs bucket for audit logs
resource "google_storage_bucket" "logs" {
  name                        = "${var.project_id}-logs"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
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

# IAM binding for log writer
resource "google_storage_bucket_iam_binding" "log_writer" {
  bucket = google_storage_bucket.logs.name
  role   = "roles/storage.legacyBucketWriter"
  members = [
    "group:cloud-storage-analytics@google.com"
  ]
}

# Main data buckets
resource "google_storage_bucket" "twitter_data_lake" {
  name                        = "${var.project_id}-twitter-data-lake"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
  logging {
    log_bucket = google_storage_bucket.logs.name
  }
  encryption {
    default_kms_key_name = var.kms_key_name
  }
  depends_on = [google_storage_bucket_iam_binding.log_writer]
}

resource "google_storage_bucket" "twitter_dataflow_meta" {
  name                        = "${var.project_id}-twitter-dataflow-meta"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
  logging {
    log_bucket = google_storage_bucket.logs.name
  }
  encryption {
    default_kms_key_name = var.kms_key_name
  }
  depends_on = [google_storage_bucket_iam_binding.log_writer]
}

resource "google_storage_bucket" "looker_data_backup" {
  name                        = "${var.project_id}-looker-backup"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
  logging {
    log_bucket = google_storage_bucket.logs.name
  }
  encryption {
    default_kms_key_name = var.kms_key_name
  }
  depends_on = [google_storage_bucket_iam_binding.log_writer]
}

# IAM bindings for private access
resource "google_storage_bucket_iam_binding" "private" {
  for_each = toset([
    google_storage_bucket.twitter_data_lake.name,
    google_storage_bucket.twitter_dataflow_meta.name,
    google_storage_bucket.looker_data_backup.name
  ])
  
  bucket = each.key
  role   = "roles/storage.legacyBucketReader"
  members = var.allowed_members
}