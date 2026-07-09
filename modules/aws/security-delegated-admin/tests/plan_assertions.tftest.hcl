# Resource-assertion tests for the aws/security-delegated-admin module.
#
# Asserts on the for_each materialization of the delegated-administrator
# registrations, which is known at plan time under mock_provider. The module
# runs from the management account with a single default provider, so a single
# mock_provider "aws" satisfies it.

mock_provider "aws" {}

variables {
  security_tooling_account_id = "111111111111"
  identity_account_id         = "222222222222"
}

run "default_set_registers_no_dedicated_resource_services" {
  command = plan

  # A no-dedicated-resource service is registered here.
  assert {
    condition     = contains(keys(aws_organizations_delegated_administrator.this), "access-analyzer.amazonaws.com")
    error_message = "access-analyzer.amazonaws.com must be registered in the default set"
  }

  # sso is delegated to the Identity account, not Security Tooling.
  assert {
    condition     = aws_organizations_delegated_administrator.this["sso.amazonaws.com"].account_id == "222222222222"
    error_message = "sso.amazonaws.com must be delegated to the identity account"
  }

  # A no-dedicated-resource service delegated to Security Tooling.
  assert {
    condition     = aws_organizations_delegated_administrator.this["config.amazonaws.com"].account_id == "111111111111"
    error_message = "config.amazonaws.com must be delegated to the security tooling account"
  }

  # Services with a dedicated admin resource must NOT be registered here.
  assert {
    condition     = !contains(keys(aws_organizations_delegated_administrator.this), "guardduty.amazonaws.com")
    error_message = "guardduty.amazonaws.com must not be registered here (uses a dedicated resource)"
  }
}

run "explicit_registrations_override_default" {
  command = plan

  variables {
    registrations = {
      "ssm.amazonaws.com" = "333333333333"
    }
  }

  assert {
    condition     = length(keys(aws_organizations_delegated_administrator.this)) == 1
    error_message = "Explicit registrations must fully override the default set"
  }

  assert {
    condition     = aws_organizations_delegated_administrator.this["ssm.amazonaws.com"].account_id == "333333333333"
    error_message = "Explicit registration account ID must be honoured"
  }
}
