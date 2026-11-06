# Variable validation tests for the iam/principal-access-boundary module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  organization_id = "123456789"
}

run "accepts_defaults" {
  command = plan
}

run "rejects_non_numeric_org" {
  command = plan

  variables {
    organization_id = "organizations/123"
  }

  expect_failures = [var.organization_id]
}

run "rejects_bad_enforcement_version" {
  command = plan

  variables {
    enforcement_version = "v1"
  }

  expect_failures = [var.enforcement_version]
}

run "rejects_non_hierarchy_resource" {
  command = plan

  variables {
    allowed_resources = ["//storage.googleapis.com/projects/_/buckets/b"]
  }

  expect_failures = [var.allowed_resources]
}

run "rejects_bad_binding_key" {
  command = plan

  variables {
    project_bindings = { "Admin_Key" = "acme-admin-abcd1234" }
  }

  expect_failures = [var.project_bindings]
}
