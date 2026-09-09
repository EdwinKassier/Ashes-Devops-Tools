# Plan assertions for the vpc-flow-logs module: verify the logging sink is planned
# with the caller-supplied name and project wired through.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id  = "mock-project"
  sink_name   = "flow-logs-sink"
  destination = "storage.googleapis.com/mock-flow-logs-bucket"
}

run "sink_wired" {
  command = plan

  assert {
    condition     = google_logging_project_sink.flow_logs_sink.name == var.sink_name
    error_message = "Logging sink name must be the caller-supplied sink_name."
  }

  assert {
    condition     = google_logging_project_sink.flow_logs_sink.project == var.project_id
    error_message = "Logging sink must be created in the caller-supplied project."
  }
}
