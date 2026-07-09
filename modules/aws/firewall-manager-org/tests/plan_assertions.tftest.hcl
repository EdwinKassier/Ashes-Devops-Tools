# Resource-assertion tests for the aws/firewall-manager-org module.
# The module declares a configuration_aliases [aws.management]; declaring a
# second mock_provider with that alias satisfies it automatically.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

variables {
  fms_admin_account_id = "111111111111"
}

run "defaults_register_admin_and_default_policy" {
  command = plan

  assert {
    condition     = length(aws_fms_admin_account.this) == 1
    error_message = "FMS admin account must be registered when enable_firewall_manager is true"
  }

  assert {
    condition     = contains(keys(aws_fms_policy.this), "security-group-audit")
    error_message = "The default security-group-audit policy must be present"
  }

  assert {
    condition     = aws_fms_policy.this["security-group-audit"].exclude_resource_tags == false
    error_message = "exclude_resource_tags must be false on the created policy"
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enable_firewall_manager = false
  }

  assert {
    condition     = length(aws_fms_admin_account.this) == 0
    error_message = "FMS admin account must not be registered when disabled"
  }

  assert {
    condition     = length(aws_fms_policy.this) == 0
    error_message = "No FMS policies must be created when disabled"
  }
}
