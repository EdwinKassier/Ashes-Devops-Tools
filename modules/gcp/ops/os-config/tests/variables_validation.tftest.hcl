# Variable validation tests for the ops/os-config module (mock_provider — no creds).

mock_provider "google" {}

variables {
  project_id = "my-project"
}

run "accepts_empty_defaults" {
  command = plan
}

run "rejects_bad_reboot_config" {
  command = plan

  expect_failures = [var.patch_deployments]

  variables {
    patch_deployments = {
      bad = { reboot_config = "MAYBE" }
    }
  }
}

run "rejects_bad_day_of_week" {
  command = plan

  expect_failures = [var.patch_deployments]

  variables {
    patch_deployments = {
      bad = { day_of_week = "Funday" }
    }
  }
}

run "rejects_bad_start_time" {
  command = plan

  expect_failures = [var.patch_deployments]

  variables {
    patch_deployments = {
      bad = { start_time = "3am" }
    }
  }
}

run "rejects_bad_project_id" {
  command = plan

  expect_failures = [var.project_id]

  variables {
    project_id = "X"
  }
}
