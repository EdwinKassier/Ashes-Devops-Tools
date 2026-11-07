# Variable validation tests for the aws/security/config-recorder-stackset module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

variables {
  target_ou_ids               = ["r-abcd"]
  security_tooling_account_id = "222222222222"
  aws_enabled_regions         = ["eu-west-2"]
  home_region                 = "eu-west-2"
  log_archive_bucket_name     = "acme-org-log-archive"
}

run "valid_inputs_accepted" {
  command = plan

  variables {
    target_ou_ids                          = ["r-abcd", "ou-abcd-workload0"]
    migration_failure_tolerance_percentage = 100
  }
}

run "empty_target_ous_rejected" {
  command         = plan
  expect_failures = [var.target_ou_ids]

  variables {
    target_ou_ids = []
  }
}

run "malformed_target_ou_rejected" {
  command         = plan
  expect_failures = [var.target_ou_ids]

  variables {
    target_ou_ids = ["123456789012"]
  }
}

run "bad_security_tooling_account_rejected" {
  command         = plan
  expect_failures = [var.security_tooling_account_id]

  variables {
    security_tooling_account_id = "123"
  }
}

run "duplicate_regions_rejected" {
  command         = plan
  expect_failures = [var.aws_enabled_regions]

  variables {
    aws_enabled_regions = ["eu-west-2", "eu-west-2"]
  }
}

run "home_region_outside_enabled_regions_rejected" {
  command         = plan
  expect_failures = [var.home_region]

  variables {
    home_region = "us-east-1"
  }
}

run "empty_bucket_rejected" {
  command         = plan
  expect_failures = [var.log_archive_bucket_name]

  variables {
    log_archive_bucket_name = " "
  }
}

run "tolerance_out_of_range_rejected" {
  command         = plan
  expect_failures = [var.migration_failure_tolerance_percentage]

  variables {
    migration_failure_tolerance_percentage = 101
  }
}
