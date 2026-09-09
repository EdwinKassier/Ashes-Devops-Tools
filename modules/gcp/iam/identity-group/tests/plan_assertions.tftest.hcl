# Plan assertions for the iam/identity-group module: verify a Cloud Identity group is
# planned under the caller-supplied customer with the expected key/display name.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  customer_id = "C01abc234"
  identity_groups = [{
    id           = "grp1"
    display_name = "Group One"
    email        = "grp1@example.com"
  }]
}

run "group_wired" {
  command = plan

  assert {
    condition     = length(google_cloud_identity_group.cloud_identity_group) == 1
    error_message = "One Cloud Identity group must be planned for one input group."
  }

  assert {
    condition     = google_cloud_identity_group.cloud_identity_group["grp1"].parent == "customers/${var.customer_id}"
    error_message = "Group parent must reference the caller-supplied customer_id."
  }

  assert {
    condition     = google_cloud_identity_group.cloud_identity_group["grp1"].display_name == "Group One"
    error_message = "Group display name must be wired from the input."
  }
}
