# Variable validation tests for the network/vpc-flow-logs module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id  = "mock-project"
  sink_name   = "flow-logs-sink"
  destination = "storage.googleapis.com/mock-flow-logs-bucket"
}

# ── destination ─────────────────────────────────────────────────────────────────

run "rejects_empty_destination" {
  command = plan

  expect_failures = [var.destination]

  variables {
    destination = ""
  }
}

# ── destination_type ───────────────────────────────────────────────────────────

run "accepts_bigquery_destination_type" {
  command = plan

  variables {
    destination_type = "bigquery"
  }
}

run "accepts_storage_destination_type" {
  command = plan

  variables {
    destination_type = "storage"
  }
}

run "accepts_pubsub_destination_type" {
  command = plan

  variables {
    destination_type = "pubsub"
  }
}

run "rejects_invalid_destination_type" {
  command = plan

  expect_failures = [var.destination_type]

  variables {
    destination_type = "logging"
  }
}

run "rejects_uppercase_destination_type" {
  command = plan

  expect_failures = [var.destination_type]

  variables {
    destination_type = "BIGQUERY"
  }
}
