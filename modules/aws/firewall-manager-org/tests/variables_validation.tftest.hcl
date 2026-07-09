# Variable validation tests for the aws/firewall-manager-org module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

variables {
  fms_admin_account_id = "111111111111"
}

run "defaults_are_valid" {
  command = plan
}

run "rejects_bad_admin_account_id" {
  command = plan

  variables {
    fms_admin_account_id = "not-an-account"
  }

  expect_failures = [var.fms_admin_account_id]
}

run "empty_admin_account_id_allowed_when_disabled" {
  command = plan

  variables {
    enable_firewall_manager = false
    fms_admin_account_id    = ""
  }
}
