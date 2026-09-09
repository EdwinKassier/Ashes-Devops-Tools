# Plan assertions for the cloud-storage module: verify a data bucket is planned in the
# caller's region and that a supplied CMEK key is wired into bucket encryption.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  region       = "us-central1"
  kms_key_name = "projects/mock-project/locations/us-central1/keyRings/test-ring/cryptoKeys/test-key"
  data_buckets = {
    primary = { name_suffix = "data" }
  }
}

run "data_bucket_region_name_and_cmek_wired" {
  command = plan

  assert {
    condition     = google_storage_bucket.data["primary"].name == "${var.project_id}-data"
    error_message = "Data bucket name must be <project>-<name_suffix>."
  }

  assert {
    condition     = google_storage_bucket.data["primary"].location == var.region
    error_message = "Data bucket must be created in the caller-supplied region."
  }

  assert {
    condition     = google_storage_bucket.data["primary"].encryption[0].default_kms_key_name == var.kms_key_name
    error_message = "Supplied CMEK key must be wired into the data bucket's default encryption."
  }

  assert {
    condition     = google_storage_bucket.data["primary"].public_access_prevention == "enforced"
    error_message = "Data bucket must enforce public access prevention."
  }
}

run "gmek_when_no_cmek" {
  command = plan

  variables {
    kms_key_name = null
  }

  assert {
    condition     = length(google_storage_bucket.data["primary"].encryption) == 0
    error_message = "With no CMEK, no explicit encryption block is planned (Google-managed/GMEK)."
  }
}
