# Example: create a project's GCS buckets — a data lake and a Dataflow staging area —
# with CMEK encryption and a shared viewer group.
# In a real deployment replace the locals below with data sources or remote state.

locals {
  project_id = "my-project-id"
  region     = "europe-west1"

  # Fully-qualified KMS key created by the kms module (or a data source)
  kms_key = "projects/my-project-id/locations/europe-west1/keyRings/app-keyring/cryptoKeys/data-encryption-key"

  # Group that needs read access to all data buckets
  data_readers = "group:data-analysts@example.com"
}

module "storage" {
  source = "../../"

  project_id   = local.project_id
  region       = local.region
  kms_key_name = local.kms_key

  data_buckets = {
    raw_events = {
      name_suffix = "raw-events"
    }
    dataflow_staging = {
      name_suffix = "dataflow-staging"
    }
  }

  allowed_members    = [local.data_readers]
  log_retention_days = 30
}

output "bucket_names" {
  description = "Map of logical key to GCS bucket name"
  value       = module.storage.bucket_names
}

output "logs_bucket" {
  description = "Audit logs sink destination bucket"
  value       = module.storage.logs_bucket_name
}
