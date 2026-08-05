# Variable validation tests for the aws/systems-manager module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: required inputs set, everything else on defaults.
  command = plan

  variables {
    log_bucket_name = "org-ssm-session-logs"
    kms_key_id      = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
  }
}

run "bad_operating_system_rejected" {
  # Reject case: an unsupported OS must trip the allowed-set validation.
  command = plan

  variables {
    log_bucket_name        = "org-ssm-session-logs"
    kms_key_id             = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    patch_operating_system = "SOLARIS"
  }

  expect_failures = [var.patch_operating_system]
}
