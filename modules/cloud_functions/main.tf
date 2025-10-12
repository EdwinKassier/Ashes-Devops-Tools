# Cloud Functions source code bucket
resource "google_storage_bucket" "functions_bucket" {
  name                        = "${var.project_id}-functions-source"
  project                     = var.project_id
  location                    = var.bucket_location
  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  logging {
    log_bucket = var.logs_bucket_name
  }

  dynamic "encryption" {
    for_each = var.kms_key_name != "" ? [1] : []
    content {
      default_kms_key_name = var.kms_key_name
    }
  }

  labels = merge(
    {
      purpose    = "cloud-functions-source"
      managed-by = "terraform"
    },
    var.labels
  )
}

# IAM binding to make the bucket private
resource "google_storage_bucket_iam_binding" "private" {
  bucket  = google_storage_bucket.functions_bucket.name
  role    = "roles/storage.legacyBucketReader"
  members = []
}

# Upload function source code
resource "google_storage_bucket_object" "archive" {
  name   = "${var.function_name}-${filemd5(var.source_archive_path)}.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = var.source_archive_path
}

# Cloud Function
resource "google_cloudfunctions_function" "function" {
  name        = var.function_name
  description = var.description
  runtime     = var.runtime
  project     = var.project_id
  region      = var.region

  available_memory_mb   = var.memory_mb
  source_archive_bucket = google_storage_bucket.functions_bucket.name
  source_archive_object = google_storage_bucket_object.archive.name
  trigger_http          = var.trigger_http
  timeout               = var.timeout_seconds
  entry_point           = var.entry_point
  service_account_email = var.service_account_email

  environment_variables = var.environment_variables

  vpc_connector                 = var.vpc_connector
  vpc_connector_egress_settings = var.vpc_connector != "" ? var.vpc_egress_settings : null

  labels = merge(
    {
      deployment-tool = "terraform"
      managed-by      = "terraform"
    },
    var.labels
  )

  # Event trigger for non-HTTP functions
  dynamic "event_trigger" {
    for_each = var.trigger_http ? [] : [1]
    content {
      event_type = var.event_trigger_type
      resource   = var.event_trigger_resource
      dynamic "failure_policy" {
        for_each = var.event_trigger_retry ? [1] : []
        content {
          retry = true
        }
      }
    }
  }
}

# IAM binding for function invocation (HTTP functions)
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count = var.trigger_http && length(var.allowed_invokers) > 0 ? length(var.allowed_invokers) : 0

  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.function.name
  role           = "roles/cloudfunctions.invoker"
  member         = var.allowed_invokers[count.index]
}

# Make function public if specified (NOT RECOMMENDED for production)
resource "google_cloudfunctions_function_iam_member" "public_invoker" {
  count = var.trigger_http && var.allow_unauthenticated ? 1 : 0

  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}
