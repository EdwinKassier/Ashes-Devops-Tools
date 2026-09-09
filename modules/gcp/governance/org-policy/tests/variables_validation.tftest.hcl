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

# Duplicate boolean constraint is rejected.
run "rejects_duplicate_boolean_constraint" {
  variables {
    parent = "organizations/123456789"
    boolean_policies = [
      { constraint = "sql.restrictPublicIp", enforce = true },
      { constraint = "sql.restrictPublicIp", enforce = false }
    ]
  }

  command = plan

  expect_failures = [var.boolean_policies]
}

# Duplicate list constraint is rejected.
run "rejects_duplicate_list_constraint" {
  variables {
    parent = "organizations/123456789"
    list_policies = [
      { constraint = "gcp.resourceLocations", deny_all = true },
      { constraint = "gcp.resourceLocations", allow_all = true }
    ]
  }

  command = plan

  expect_failures = [var.list_policies]
}

# Custom constraint is materialized into a google_org_policy_custom_constraint.
run "custom_constraint_created" {
  variables {
    parent = "organizations/123456789"
    custom_constraints = [
      {
        name           = "custom.requirePrivateGkeNodes"
        display_name   = "Require private GKE nodes"
        description    = "Deny GKE clusters without private nodes"
        action_type    = "DENY"
        condition      = "resource.privateClusterConfig.enablePrivateNodes == false"
        method_types   = ["CREATE", "UPDATE"]
        resource_types = ["container.googleapis.com/Cluster"]
      }
    ]
  }

  command = plan

  assert {
    condition     = length(google_org_policy_custom_constraint.custom_constraints) == 1
    error_message = "Expected one custom org-policy constraint to be planned"
  }
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
