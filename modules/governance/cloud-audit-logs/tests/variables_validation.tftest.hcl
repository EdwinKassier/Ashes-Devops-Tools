# Variable validation tests for the cloud-audit-logs module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
}

# ── log_retention_days ─────────────────────────────────────────────────────────

run "accepts_valid_retention_days" {
  command = plan

  variables {
    log_retention_days = 365
  }
}

run "accepts_minimum_retention_days" {
  command = plan

  variables {
    log_retention_days = 1
  }
}

run "rejects_zero_retention_days" {
  command = plan

  expect_failures = [var.log_retention_days]

  variables {
    log_retention_days = 0
  }
}

run "rejects_negative_retention_days" {
  command = plan

  expect_failures = [var.log_retention_days]

  variables {
    log_retention_days = -30
  }
}

# ── bigquery_retention_days ────────────────────────────────────────────────────

run "accepts_valid_bigquery_retention" {
  command = plan

  variables {
    bigquery_retention_days = 90
  }
}

run "rejects_zero_bigquery_retention" {
  command = plan

  expect_failures = [var.bigquery_retention_days]

  variables {
    bigquery_retention_days = 0
  }
}

# ── kms_key_name ───────────────────────────────────────────────────────────────

run "accepts_null_kms_key" {
  command = plan

  variables {
    kms_key_name = null
  }
}

run "accepts_valid_kms_key_name" {
  command = plan

  variables {
    kms_key_name = "projects/my-project/locations/us/keyRings/my-ring/cryptoKeys/my-key"
  }
}

run "rejects_malformed_kms_key_name" {
  command = plan

  expect_failures = [var.kms_key_name]

  variables {
    kms_key_name = "my-kms-key"
  }
}

# ── org_id ─────────────────────────────────────────────────────────────────────

run "accepts_null_org_id" {
  command = plan

  variables {
    org_id = null
  }
}

run "accepts_numeric_org_id" {
  command = plan

  variables {
    org_id = "123456789"
  }
}

run "rejects_org_id_with_prefix" {
  command = plan

  expect_failures = [var.org_id]

  variables {
    org_id = "organizations/123456789"
  }
}

run "rejects_alphabetic_org_id" {
  command = plan

  expect_failures = [var.org_id]

  variables {
    org_id = "my-org"
  }
}
