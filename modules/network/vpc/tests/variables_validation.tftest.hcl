# Variable validation tests for the vpc module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
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
