mock_provider "google" {}

# Valid organization-scoped parent is accepted.
run "valid_org_parent" {
  variables {
    parent = "organizations/123456789"
    boolean_policies = [
      {
        constraint = "sql.restrictPublicIp"
        enforce    = true
      }
    ]
  }

  command = plan

  assert {
    condition     = length(google_org_policy_policy.boolean_policies) == 1
    error_message = "Expected one boolean policy to be planned"
  }
}

# Valid folder-scoped parent is accepted.
run "valid_folder_parent" {
  variables {
    parent = "folders/987654321"
  }

  command = plan
}

# Valid project-scoped parent is accepted.
run "valid_project_parent" {
  variables {
    parent = "projects/111222333"
  }

  command = plan
}

# Invalid parent format (missing numeric ID) is rejected.
run "invalid_parent_no_id" {
  variables {
    parent = "organizations/"
  }

  command = plan

  expect_failures = [var.parent]
}

# Invalid parent format (wrong resource type) is rejected.
run "invalid_parent_wrong_type" {
  variables {
    parent = "billing/abc123"
  }

  command = plan

  expect_failures = [var.parent]
}

# List policy with deny_all creates exactly one policy resource.
run "list_policy_deny_all" {
  variables {
    parent = "organizations/123456789"
    list_policies = [
      {
        constraint     = "gcp.resourceLocations"
        allow_all      = false
        deny_all       = true
        allowed_values = []
        denied_values  = []
      }
    ]
  }

  command = plan

  assert {
    condition     = length(google_org_policy_policy.list_policies) == 1
    error_message = "Expected one list policy to be planned"
  }
}
