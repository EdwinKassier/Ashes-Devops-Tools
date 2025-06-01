# Cloud Functions source code bucket
resource "google_storage_bucket" "functions_bucket" {
  name                        = "CloudFunctionStorage"
  location                    = "US"
  force_destroy               = false
  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
  logging {
    log_bucket = "logs-bucket-name"
  }
  encryption {
    default_kms_key_name = "kms-key-name"
  }
}

# IAM binding to make the bucket private
resource "google_storage_bucket_iam_binding" "private" {
  bucket = google_storage_bucket.functions_bucket.name
  role   = "roles/storage.legacyBucketReader"
  members = []
}

# Cloud Function
resource "google_cloudfunctions_function" "function" {
  name        = "twitter-pipeline-origin"
  description = "Entry point to twitter pipeline"
  runtime     = "python310"
  project     = "project-id"
  region      = "US"

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.functions_bucket.name
  source_archive_object = google_storage_bucket_object.archive.name
  trigger_http          = true
  timeout               = 60
  entry_point           = "Exract_Twitter_Data"
  service_account_email = ""
  
  environment_variables = {}
  
  vpc_connector = ""
  
  labels = {
    "deployment-tool" = "terraform"
  }
}

# IAM binding for function invocation
resource "google_cloudfunctions_function_iam_binding" "invoker" {
  count = 0
  
  project        = "project-id"
  region         = "US"
  cloud_function = google_cloudfunctions_function.function.name
  role           = "roles/cloudfunctions.invoker"
  members        = []
}

# IAM binding for service account
resource "google_cloudfunctions_function_iam_member" "service_account" {
  count = 0
  
  project        = "project-id"
  region         = "US"
  cloud_function = google_cloudfunctions_function.function.name
  role           = "roles/cloudfunctions.serviceAgent"
  member         = ""
}

# IAM entry for all users to invoke the function
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.function.project
  region         = google_cloudfunctions_function.function.region
  cloud_function = google_cloudfunctions_function.function.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

resource "google_storage_bucket_object" "archive" {
  name   = "index.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = "./path/to/zip/file/which/contains/code"
}