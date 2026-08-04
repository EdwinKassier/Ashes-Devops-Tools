# Variable validation tests for the stages/projects module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_prefix          = "my-org"
  organization_name       = "example"
  default_billing_account = "ABCDEF-123456-789012"
  admin_project_id        = "mock-admin-project"
  suffix                  = "abcd1234"
  folders = {
    dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" }
  }
  environments = {
    dev = {
      display_name = "Development"
      description  = "Development environment"
      projects = {
        host = {
          name   = "host"
          labels = {}
        }
      }
    }
  }
}

run "accepts_valid_inputs" {
  command = plan
}

run "rejects_invalid_billing_account_format" {
  command         = plan
  expect_failures = [var.default_billing_account]
  variables {
    default_billing_account = "abcdef-123456-789012"
  }
}

run "rejects_billing_account_missing_hyphens" {
  command         = plan
  expect_failures = [var.default_billing_account]
  variables {
    default_billing_account = "ABCDEF123456789012"
  }
}

run "rejects_empty_environments" {
  command         = plan
  expect_failures = [var.environments]
  variables {
    environments = {}
  }
}
