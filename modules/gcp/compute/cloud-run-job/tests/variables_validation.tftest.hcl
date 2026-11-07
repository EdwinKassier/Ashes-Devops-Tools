# Variable validation tests for the cloud-run-job module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id            = "mock-project-id"
  location              = "europe-west1"
  name                  = "mock-job"
  image                 = "europe-west1-docker.pkg.dev/mock-project-id/apps/job:1.0.0"
  service_account_email = "job-sa@mock-project-id.iam.gserviceaccount.com"
}

run "valid_inputs_accepted" {
  command = plan
}

run "invalid_project_id_rejected" {
  command         = plan
  expect_failures = [var.project_id]
  variables { project_id = "INVALID PROJECT!" }
}

run "invalid_location_rejected" {
  command         = plan
  expect_failures = [var.location]
  variables { location = "not a region" }
}

run "invalid_name_rejected" {
  command         = plan
  expect_failures = [var.name]
  variables { name = "Bad_Name" }
}

run "blank_image_rejected" {
  command         = plan
  expect_failures = [var.image]
  variables { image = "  " }
}

run "non_sa_email_rejected" {
  command         = plan
  expect_failures = [var.service_account_email]
  variables { service_account_email = "someone@example.com" }
}

run "zero_task_count_rejected" {
  command         = plan
  expect_failures = [var.task_count]
  variables { task_count = 0 }
}

run "zero_parallelism_rejected" {
  command         = plan
  expect_failures = [var.parallelism]
  variables { parallelism = 0 }
}

run "too_many_retries_rejected" {
  command         = plan
  expect_failures = [var.max_retries]
  variables { max_retries = 11 }
}

run "bad_timeout_rejected" {
  command         = plan
  expect_failures = [var.timeout]
  variables { timeout = "10m" }
}

run "bad_egress_rejected" {
  command         = plan
  expect_failures = [var.vpc_access]
  variables { vpc_access = { egress = "SOME_TRAFFIC" } }
}
