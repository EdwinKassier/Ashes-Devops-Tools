mock_provider "google" {}

variables {
  project_id   = "my-project"
  service_id   = "svc-123"
  slo_id       = "api-availability"
  display_name = "API availability"
}

run "rejects_invalid_slo_id" {
  command = plan
  variables {
    slo_id = "Bad_ID"
  }
  expect_failures = [var.slo_id]
}

run "rejects_invalid_sli_type" {
  command = plan
  variables {
    sli_type = "throughput"
  }
  expect_failures = [var.sli_type]
}

run "rejects_goal_out_of_range" {
  command = plan
  variables {
    goal = 1.5
  }
  expect_failures = [var.goal]
}

run "accepts_valid_inputs" {
  command = plan
}
