# Variable validation tests for the governance/scc module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  org_id     = "123456789"
  project_id = "mock-project"
}

# ── kms_key_name ───────────────────────────────────────────────────────────────

run "accepts_null_kms_key_name" {
  command = plan

  variables {
    kms_key_name = null
  }
}

run "accepts_valid_kms_key_name" {
  command = plan

  variables {
    kms_key_name = "projects/my-project/locations/global/keyRings/scc-ring/cryptoKeys/scc-key"
  }
}

run "accepts_regional_kms_key_name" {
  command = plan

  variables {
    kms_key_name = "projects/my-project/locations/us-central1/keyRings/my-ring/cryptoKeys/my-key"
  }
}

run "rejects_malformed_kms_key_name" {
  command = plan

  expect_failures = [var.kms_key_name]

  variables {
    kms_key_name = "my-project/scc-key"
  }
}

run "rejects_partial_kms_key_name" {
  command = plan

  expect_failures = [var.kms_key_name]

  variables {
    kms_key_name = "projects/my-project/locations/global/keyRings/scc-ring"
  }
}
