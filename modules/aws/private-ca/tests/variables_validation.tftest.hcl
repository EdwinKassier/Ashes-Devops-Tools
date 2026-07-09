# Variable validation tests for the aws/private-ca module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # The disabled defaults must pass all validations.
  command = plan
}

run "bad_ca_type_rejected" {
  command = plan

  variables {
    enable_private_ca = true
    org_arn           = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
    ca_type           = "INTERMEDIATE"
  }

  expect_failures = [var.ca_type]
}

run "out_of_range_deletion_window_rejected" {
  command = plan

  variables {
    enable_private_ca               = true
    org_arn                         = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
    permanent_deletion_time_in_days = 60
  }

  expect_failures = [var.permanent_deletion_time_in_days]
}
