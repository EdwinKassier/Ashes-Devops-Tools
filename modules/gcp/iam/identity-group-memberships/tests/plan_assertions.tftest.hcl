# Plan assertions for the iam/identity-group-memberships module: verify a membership
# is planned for each caller-supplied member.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  members = [{
    group_id  = "group-id-123"
    member_id = "user@example.com"
    roles     = ["MEMBER"]
  }]
}

run "membership_planned" {
  command = plan

  assert {
    condition     = length(google_cloud_identity_group_membership.membership) == 1
    error_message = "One membership must be planned for one input member."
  }
}
