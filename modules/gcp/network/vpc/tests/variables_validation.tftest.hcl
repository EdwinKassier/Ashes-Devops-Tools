# Variable validation tests for the vpc module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  vpc_name   = "mock-vpc"
}

# ── routing_mode ───────────────────────────────────────────────────────────────

run "accepts_regional_routing_mode" {
  command = plan

  variables {
    routing_mode = "REGIONAL"
  }
}

run "accepts_global_routing_mode" {
  command = plan

  variables {
    routing_mode = "GLOBAL"
  }
}

run "rejects_invalid_routing_mode" {
  command = plan

  expect_failures = [var.routing_mode]

  variables {
    routing_mode = "LOCAL"
  }
}

# ── enable_deletion_protection ─────────────────────────────────────────────────

run "deletion_protection_guard_created_when_enabled" {
  command = plan

  variables {
    enable_deletion_protection = true
  }

  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 1
    error_message = "Guard resource must be created when enable_deletion_protection = true."
  }
}

run "deletion_protection_guard_absent_when_disabled" {
  command = plan

  variables {
    enable_deletion_protection = false
  }

  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 0
    error_message = "Guard resource must not be created when enable_deletion_protection = false."
  }
}
