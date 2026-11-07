# Variable validation tests for the aws/securityhub-org module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

run "defaults_accepted" {
  # Accept case: valid ids plus module defaults must pass all validations.
  command = plan

  variables {
    security_tooling_account_id = "111111111111"
    org_root_id                 = "r-abc1"
  }
}

run "bad_account_id_rejected" {
  # Reject case: a non-12-digit account id must trip the regex validation.
  command = plan

  variables {
    security_tooling_account_id = "123"
    org_root_id                 = "r-abc1"
  }

  expect_failures = [var.security_tooling_account_id]
}

# EC2.6 (VPC flow logging enabled) is enabled through the CIS 3.0 and NIST
# standards and backs the flow-log detection; it must never be disabled.
run "ec2_6_cannot_be_disabled" {
  command = plan

  variables {
    security_tooling_account_id  = "111111111111"
    org_root_id                  = "r-abc1"
    disabled_control_identifiers = ["IAM.6", "EC2.6"]
  }

  expect_failures = [var.disabled_control_identifiers]
}

run "other_controls_can_be_disabled" {
  command = plan

  variables {
    security_tooling_account_id  = "111111111111"
    org_root_id                  = "r-abc1"
    disabled_control_identifiers = ["IAM.6", "EC2.8"]
  }
}
