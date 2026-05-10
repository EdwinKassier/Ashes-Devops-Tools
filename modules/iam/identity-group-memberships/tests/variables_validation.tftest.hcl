# Variable validation tests for the iam/identity_group_memberships module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

# Base variables — empty members list is valid (default)
variables {}

# ── members.roles ──────────────────────────────────────────────────────────────

run "accepts_member_role" {
  command = plan

  variables {
    members = [{
      group_id  = "group-id-123"
      member_id = "user@example.com"
      roles     = ["MEMBER"]
    }]
  }
}

run "accepts_manager_role" {
  command = plan

  variables {
    members = [{
      group_id  = "group-id-123"
      member_id = "manager@example.com"
      roles     = ["MANAGER"]
    }]
  }
}

run "accepts_owner_role" {
  command = plan

  variables {
    members = [{
      group_id  = "group-id-123"
      member_id = "owner@example.com"
      roles     = ["OWNER"]
    }]
  }
}

run "accepts_multiple_roles_on_same_member" {
  command = plan

  variables {
    members = [{
      group_id  = "group-id-123"
      member_id = "manager@example.com"
      roles     = ["MEMBER", "MANAGER"]
    }]
  }
}

run "accepts_empty_members_list" {
  command = plan

  variables {
    members = []
  }
}

run "rejects_invalid_role" {
  command = plan

  expect_failures = [var.members]

  variables {
    members = [{
      group_id  = "group-id-123"
      member_id = "user@example.com"
      roles     = ["ADMIN"]
    }]
  }
}

run "rejects_invalid_role_in_mixed_list" {
  command = plan

  expect_failures = [var.members]

  variables {
    members = [{
      group_id  = "group-id-123"
      member_id = "user@example.com"
      roles     = ["MEMBER", "SUPERUSER"]
    }]
  }
}
