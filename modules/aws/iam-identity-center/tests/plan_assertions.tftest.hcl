# Resource-assertion tests for the aws/iam-identity-center module.
#
# Mocks the discovered Identity Center instances data source with a known ARN so
# local.instance_arn is deterministic, then asserts on plan-known attributes
# (session_duration derived from the default permission_sets, and the
# principal_type of an assignment). Provider-computed attributes (permission set
# ARNs) are deliberately not asserted on.

mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-0000000000000000"]
      identity_store_ids = ["d-0000000000"]
    }
  }
}

run "default_permission_sets_have_valid_session_duration" {
  command = plan

  assert {
    condition     = aws_ssoadmin_permission_set.this["AdministratorAccess"].session_duration == "PT1H"
    error_message = "Default AdministratorAccess permission set must have session_duration PT1H"
  }

  assert {
    condition     = can(regex("^PT([0-9]|1[0-2])H$", aws_ssoadmin_permission_set.this["ReadOnly"].session_duration))
    error_message = "Default ReadOnly session_duration must match the <=PT12H ISO-8601 hour pattern"
  }

  assert {
    condition     = local.instance_arn == "arn:aws:sso:::instance/ssoins-0000000000000000"
    error_message = "instance_arn must be resolved from the discovered Identity Center instance"
  }
}

run "group_assignment_is_planned" {
  command = plan

  variables {
    assignments = {
      x = {
        permission_set = "AdministratorAccess"
        principal_type = "GROUP"
        principal_id   = "00000000-0000-0000-0000-000000000000"
        account_id     = "111111111111"
      }
    }
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["x"].principal_type == "GROUP"
    error_message = "The x assignment must bind a GROUP principal"
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["x"].target_type == "AWS_ACCOUNT"
    error_message = "Account assignments must target an AWS account"
  }
}
