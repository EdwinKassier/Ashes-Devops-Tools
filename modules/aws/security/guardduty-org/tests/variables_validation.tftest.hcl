# Variable validation tests for the aws/guardduty-org module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

variables {
  security_tooling_account_id = "111111111111"
}

run "defaults_are_valid" {
  command = plan
}

run "rejects_non_numeric_account_id" {
  command = plan

  variables {
    security_tooling_account_id = "bad"
  }

  expect_failures = [var.security_tooling_account_id]
}

run "unknown_agent_type_rejected" {
  command = plan

  variables {
    runtime_monitoring_agent_management = ["LAMBDA_AGENT_MANAGEMENT"]
  }

  expect_failures = [var.runtime_monitoring_agent_management]
}
