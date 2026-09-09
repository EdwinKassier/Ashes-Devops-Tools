# Plan assertions for the cloud-armor module: verify the security policy is planned
# with the caller-supplied name and project wired through.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id  = "mock-project"
  policy_name = "mock-armor-policy"
}

run "security_policy_wired" {
  command = plan

  assert {
    condition     = google_compute_security_policy.policy.name == var.policy_name
    error_message = "Security policy name must be the caller-supplied policy_name."
  }

  assert {
    condition     = google_compute_security_policy.policy.project == var.project_id
    error_message = "Security policy must be created in the caller-supplied project."
  }
}
