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

  assert {
    # Non-vacuous: the standing policy body must be a genuine deny-all -
    # Effect=Deny on Action=* - not merely present. jsonencode sorts keys,
    # so the rendered form is {"Statement":[{"Action":"*","Effect":"Deny",...
    condition     = can(regex("\"Effect\":\"Deny\"", aws_iam_role_policy.break_glass_standing[0].policy)) && can(regex("\"Action\":\"\\*\"", aws_iam_role_policy.break_glass_standing[0].policy))
    error_message = "Break-glass standing policy must deny all actions (Effect=Deny, Action=*)."
  }
}

# Boundary propagation (tfc-oidc-baseline): the module-wide
# permissions_boundary_arn lands on every role that does not set its own, a
# per-role boundary wins, and the break-glass role carries the module default.
run "permissions_boundary_propagated" {
  command = plan

  variables {
    roles = {
      inherits = {
        trust_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::111111111111:root\"},\"Action\":\"sts:AssumeRole\"}]}"
      }
      own = {
        trust_policy         = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::111111111111:root\"},\"Action\":\"sts:AssumeRole\"}]}"
        permissions_boundary = "arn:aws:iam::123456789012:policy/custom-boundary"
      }
    }
    break_glass_trusted_principals = ["arn:aws:iam::222222222222:role/admin"]
    permissions_boundary_arn       = "arn:aws:iam::123456789012:policy/tfc-apply-boundary"
  }

  assert {
    condition     = aws_iam_role.this["inherits"].permissions_boundary == "arn:aws:iam::123456789012:policy/tfc-apply-boundary"
    error_message = "A role without its own boundary must inherit permissions_boundary_arn."
  }

  assert {
    condition     = aws_iam_role.this["own"].permissions_boundary == "arn:aws:iam::123456789012:policy/custom-boundary"
    error_message = "A role's own permissions_boundary must take precedence over the module default."
  }

  assert {
    condition     = aws_iam_role.break_glass[0].permissions_boundary == "arn:aws:iam::123456789012:policy/tfc-apply-boundary"
    error_message = "The break-glass role must carry permissions_boundary_arn."
  }
}
