mock_provider "google" {}

# Minimum required variables shared across all runs
variables {
  project_id   = "mock-project"
  region       = "us-central1"
  kms_key_name = "projects/mock-project/locations/us-central1/keyRings/test-ring/cryptoKeys/test-key"
}

# ── Bucket creation ────────────────────────────────────────────────────────────

run "creates_fixed_infrastructure_buckets" {
  # Even with no data_buckets, the access-logs and logs buckets must exist
  command = plan

  assert {
    condition     = google_storage_bucket.access_logs.name == "mock-project-bucket-access-logs"
    error_message = "access_logs bucket name must be '<project_id>-bucket-access-logs'"
  }

  assert {
    condition     = google_storage_bucket.logs.name == "mock-project-logs"
    error_message = "logs bucket name must be '<project_id>-logs'"
  }
}

run "creates_data_buckets_with_correct_names" {
  command = plan

  variables {
    data_buckets = {
      raw   = { name_suffix = "raw-events" }
      stage = { name_suffix = "staging-data" }
    }
  }

  assert {
    condition     = length(google_storage_bucket.data) == 2
    error_message = "Expected exactly 2 data buckets"
  }

  assert {
    condition     = google_storage_bucket.data["raw"].name == "mock-project-raw-events"
    error_message = "Data bucket name must be '<project_id>-<name_suffix>'"
  }

  assert {
    condition     = google_storage_bucket.data["stage"].name == "mock-project-staging-data"
    error_message = "Data bucket name must be '<project_id>-<name_suffix>'"
  }
}

run "creates_no_data_buckets_by_default" {
  command = plan

  assert {
    condition     = length(google_storage_bucket.data) == 0
    error_message = "No data buckets should be created when data_buckets is empty"
  }
}

# ── Encryption ────────────────────────────────────────────────────────────────

run "all_buckets_use_cmek" {
  command = plan

  variables {
    data_buckets = {
      test = { name_suffix = "test-data" }
    }
  }

  assert {
    condition     = google_storage_bucket.access_logs.encryption[0].default_kms_key_name == var.kms_key_name
    error_message = "access_logs bucket must use the provided KMS key"
  }

  assert {
    condition     = google_storage_bucket.logs.encryption[0].default_kms_key_name == var.kms_key_name
    error_message = "logs bucket must use the provided KMS key"
  }

  assert {
    condition     = google_storage_bucket.data["test"].encryption[0].default_kms_key_name == var.kms_key_name
    error_message = "data buckets must use the provided KMS key"
  }
}

# ── Variable validation ────────────────────────────────────────────────────────

run "rejects_null_region" {
  # region has no default — omitting it (null) must fail clearly, not plan a null-location bucket
  command = plan

  expect_failures = [var.region]

  variables {
    region = null
  }
}

run "rejects_invalid_kms_key_format" {
  command = plan

  expect_failures = [var.kms_key_name]

  variables {
    kms_key_name = "not-a-valid-kms-key-name"
  }
}

run "rejects_kms_key_missing_cryptokeys_segment" {
  command = plan

  expect_failures = [var.kms_key_name]

  variables {
    kms_key_name = "projects/p/locations/l/keyRings/r"
  }
}

run "rejects_zero_log_retention_days" {
  command = plan

  expect_failures = [var.log_retention_days]

  variables {
    log_retention_days = 0
  }
}

run "rejects_negative_log_retention_days" {
  command = plan

  expect_failures = [var.log_retention_days]

  variables {
    log_retention_days = -1
  }
}

run "accepts_minimum_log_retention_days" {
  command = plan

  variables {
    log_retention_days = 1
  }
}
