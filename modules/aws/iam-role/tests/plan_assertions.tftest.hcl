# Resource-assertion tests for the aws/iam-role module.
#
# Asserts on configured attributes that are known at plan time under
# mock_provider (session duration, the jsonencoded break-glass trust policy,
# and the presence/count of the deny-all standing policy). Provider-computed
# attributes (arns, ids) are deliberately not asserted on.

mock_provider "aws" {}

run "workload_role_and_break_glass_defaults" {
  command = plan

  variables {
    roles = {
      x = {
        trust_policy         = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::111111111111:root\"},\"Action\":\"sts:AssumeRole\"}]}"
        max_session_duration = 7200
      }
    }
    break_glass_trusted_principals = ["arn:aws:iam::222222222222:role/admin"]
  }

  assert {
    condition     = aws_iam_role.this["x"].max_session_duration == 7200
    error_message = "Workload role x must carry its configured 7200s max_session_duration."
  }

  assert {
    condition     = can(regex("aws:MultiFactorAuthPresent", aws_iam_role.break_glass[0].assume_role_policy))
    error_message = "Break-glass trust policy must require MFA to be present."
  }

  assert {
    condition     = can(regex("aws:MultiFactorAuthAge", aws_iam_role.break_glass[0].assume_role_policy))
    error_message = "Break-glass trust policy must constrain the MFA session age."
  }

  assert {
    condition     = length(aws_iam_role_policy.break_glass_standing) == 1
    error_message = "With break_glass_active=false the deny-all standing policy must be present."
  }
}
