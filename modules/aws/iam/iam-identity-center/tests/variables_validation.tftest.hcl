# Variable validation tests for the aws/iam-identity-center module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-0000000000000000"]
      identity_store_ids = ["d-0000000000"]
    }
  }
}

run "defaults_accepted" {
  # Accept case: the default permission sets must pass all validations.
  command = plan
}

run "session_duration_over_12h_rejected" {
  # Reject case: PT13H exceeds the PT12H AWS maximum and must trip the regex.
  command = plan

  variables {
    permission_sets = {
      TooLong = {
        description      = "invalid duration"
        session_duration = "PT13H"
      }
    }
  }

  expect_failures = [var.permission_sets]
}

run "bad_principal_type_rejected" {
  # Reject case: principal_type must be GROUP or USER.
  command = plan

  variables {
    assignments = {
      bad = {
        permission_set = "AdministratorAccess"
        principal_type = "ROLE"
        principal_id   = "00000000-0000-0000-0000-000000000000"
        account_id     = "111111111111"
      }
    }
  }

  expect_failures = [var.assignments]
}
