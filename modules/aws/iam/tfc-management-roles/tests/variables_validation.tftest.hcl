# Variable validation for tfc-management-roles.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  tfc_organization = "acme"
}

run "wildcard_organization_rejected" {
  command = plan
  variables {
    tfc_organization = "acme*"
  }
  expect_failures = [var.tfc_organization]
}

run "unknown_workspace_without_policy_rejected" {
  command = plan
  variables {
    workspaces = { "aws-network" = {} }
  }
  expect_failures = [var.workspaces]
}

run "aws_organization_rejected" {
  command = plan
  variables {
    workspaces = { "aws-organization" = { apply_policy_json = "{}" } }
  }
  expect_failures = [var.workspaces]
}

run "short_session_rejected" {
  command = plan
  variables {
    max_session_duration = 900
  }
  expect_failures = [var.max_session_duration]
}
