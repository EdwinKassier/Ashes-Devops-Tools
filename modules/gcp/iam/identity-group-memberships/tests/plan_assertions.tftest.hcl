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

run "for_each_keys_and_roles_derived" {
  command = plan

  variables {
    members = [
      { group_id = "groups/admins", member_id = "alice@example.com", roles = ["MEMBER", "MANAGER"] },
      { group_id = "groups/admins", member_id = "bob@example.com", roles = ["MEMBER"] },
      { group_id = "groups/readers", member_id = "alice@example.com", roles = ["MEMBER"] },
    ]
  }

  assert {
    condition = toset(keys(google_cloud_identity_group_membership.membership)) == toset([
      "groups/admins-alice@example.com",
      "groups/admins-bob@example.com",
      "groups/readers-alice@example.com",
    ])
    error_message = "Memberships must be keyed '<group_id>-<member_id>' so the same member can join multiple groups."
  }

  assert {
    condition     = google_cloud_identity_group_membership.membership["groups/admins-alice@example.com"].preferred_member_key[0].id == "alice@example.com"
    error_message = "member_id must map to preferred_member_key.id."
  }

  assert {
    condition     = toset([for r in google_cloud_identity_group_membership.membership["groups/admins-alice@example.com"].roles : r.name]) == toset(["MEMBER", "MANAGER"])
    error_message = "One roles block must be rendered per supplied role."
  }

  assert {
    condition     = length(google_cloud_identity_group_membership.membership["groups/readers-alice@example.com"].roles) == 1
    error_message = "Roles must be scoped per membership, not shared across a member's groups."
  }
}

run "no_members_no_memberships" {
  command = plan

  variables {
    members = []
  }

  assert {
    condition     = length(google_cloud_identity_group_membership.membership) == 0
    error_message = "An empty members list must plan no memberships."
  }
}
