# Example: create a project's GCS buckets — a data lake and a Dataflow staging area —
# with CMEK encryption and a shared viewer group.
#
# kms_key_name is OPTIONAL. Omit it to use Google-managed encryption (GMEK).
# For compliance environments (PCI-DSS, HIPAA, FedRAMP) always supply a CMEK key
# and ensure the Cloud Storage service account has
# roles/cloudkms.cryptoKeyEncrypterDecrypter on the key.
#
# In a real deployment replace the locals below with data sources or remote state.

locals {
  project_id = "my-project-id"
  region     = "europe-west1"

  # Fully-qualified KMS key from the governance/kms module (or a data source).
  # Remove this and the kms_key_name argument below to use Google-managed encryption.
  kms_key = "projects/my-project-id/locations/europe-west1/keyRings/app-keyring/cryptoKeys/data-encryption-key"

  # Group that needs read access to all data buckets
  data_readers = "group:data-analysts@example.com"
}

module "storage" {
  source = "../../"

  project_id = local.project_id
  region     = local.region

  # Optional: supply a CMEK key for customer-managed encryption.
  # Leave unset (or set to null) to use Google-managed encryption.
  kms_key_name = local.kms_key

  data_buckets = {
    raw_events = {
      name_suffix = "raw-events"
    }
    dataflow_staging = {
      name_suffix    = "dataflow-staging"
      retention_days = 90 # hard-delete objects after 90 days
    }
  }

  allowed_members    = [local.data_readers]
  log_retention_days = 30
}
