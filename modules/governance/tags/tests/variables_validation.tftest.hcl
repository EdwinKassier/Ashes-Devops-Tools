# Variable validation tests for the governance/tags module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  org_id = "123456789"
  tags = {
    environment = ["dev", "prod"]
  }
}

run "accepts_valid_inputs" {
  command = plan
}

run "rejects_org_id_with_prefix" {
  command         = plan
  expect_failures = [var.org_id]
  variables {
    org_id = "organizations/123456789"
  }
}

run "rejects_non_numeric_org_id" {
  command         = plan
  expect_failures = [var.org_id]
  variables {
    org_id = "abc123"
  }
}

run "rejects_empty_tags" {
  command         = plan
  expect_failures = [var.tags]
  variables {
    tags = {}
  }
}
