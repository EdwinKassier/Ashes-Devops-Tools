# Plan assertions for the shared-vpc-service module: verify the service project is
# attached to the caller-supplied Shared VPC host project.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  host_project_id    = "mock-host-project"
  service_project_id = "mock-service-project"
}

run "service_project_attachment_wired" {
  command = plan

  assert {
    condition     = google_compute_shared_vpc_service_project.service_project.host_project == var.host_project_id
    error_message = "Attachment must reference the caller-supplied host project."
  }

  assert {
    condition     = google_compute_shared_vpc_service_project.service_project.service_project == var.service_project_id
    error_message = "Attachment must reference the caller-supplied service project."
  }
}
