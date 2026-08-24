# Variable validation tests for the private-ca module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  ca_pool_name = "test-pool"
  name         = "test-ca"
}

# ── ca_type ─────────────────────────────────────────────────────────────────

run "accepts_root_ca_type" {
  command = plan

  variables {
    ca_type = "ROOT"
  }
}

run "accepts_subordinate_ca_type" {
  command = plan

  variables {
    ca_type = "SUBORDINATE"
  }
}

run "rejects_invalid_ca_type" {
  command = plan

  expect_failures = [var.ca_type]

  variables {
    ca_type = "INTERMEDIATE"
  }
}

# ── tier ──────────────────────────────────────────────────────────────────--

run "accepts_enterprise_tier" {
  command = plan

  variables {
    tier = "ENTERPRISE"
  }
}

run "accepts_devops_tier" {
  command = plan

  variables {
    tier = "DEVOPS"
  }
}

run "rejects_invalid_tier" {
  command = plan

  expect_failures = [var.tier]

  variables {
    tier = "PREMIUM"
  }
}
