# Variable validation tests for the iam/deny-policy module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  parent = "cloudresourcemanager.googleapis.com%2Forganizations%2F123456789"
}

run "accepts_valid_org_attachment_point" {
  command = plan

  variables {
    deny_policies = []
  }
}

run "rejects_unencoded_parent" {
  command = plan

  expect_failures = [var.parent]

  variables {
    parent        = "cloudresourcemanager.googleapis.com/organizations/123456789"
    deny_policies = []
  }
}

run "rejects_duplicate_policy_names" {
  command = plan

  expect_failures = [var.deny_policies]

  variables {
    deny_policies = [
      { name = "dup", rules = [{ denied_principals = ["principalSet://goog/public:all"], denied_permissions = ["iam.googleapis.com/serviceAccountKeys.create"] }] },
      { name = "dup", rules = [{ denied_principals = ["principalSet://goog/public:all"], denied_permissions = ["iam.googleapis.com/serviceAccountKeys.upload"] }] },
    ]
  }
}

run "rejects_policy_with_no_rules" {
  command = plan

  expect_failures = [var.deny_policies]

  variables {
    deny_policies = [
      { name = "empty", rules = [] },
    ]
  }
}
