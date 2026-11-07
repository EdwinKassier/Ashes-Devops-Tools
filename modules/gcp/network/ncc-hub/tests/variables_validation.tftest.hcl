# Variable validation tests for network/ncc-hub (mock provider).

mock_provider "google" {}

variables {
  project_id = "mock-hub-project"
  name       = "mock-hub"
}

run "accepts_star_and_defaults" {
  command = plan
}

run "rejects_unknown_topology" {
  command = plan

  variables {
    preset_topology = "HYBRID_INSPECTION"
  }

  expect_failures = [var.preset_topology]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Bad_Hub"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_project_id" {
  command = plan

  variables {
    project_id = "x"
  }

  expect_failures = [var.project_id]
}
