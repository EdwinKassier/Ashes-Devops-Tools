# Example: Cloud Storage module with two application data buckets and
# CMEK encryption. The module also creates fixed access-log and audit-log
# buckets in the same project.
# Replace project_id and kms_key_name with real values.

module "storage" {
  source = "../../modules/cloud_storage"

  project_id = "my-project-id"
  region     = "europe-west1"

  kms_key_name = "projects/my-project-id/locations/europe-west1/keyRings/app-keyring/cryptoKeys/app-data-key"

  data_buckets = {
    "raw-ingest" = {
      name_suffix   = "raw-ingest"
      force_destroy = false
    }
    "processed" = {
      name_suffix   = "processed"
      force_destroy = false
    }
  }

  allowed_members    = ["serviceAccount:pipeline@my-project-id.iam.gserviceaccount.com"]
  log_retention_days = 30
}

