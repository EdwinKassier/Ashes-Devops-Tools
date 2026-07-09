# Resource-assertion tests for the aws/securityhub-org module.
#
# Asserts on configured attributes known at plan time under mock_provider. The
# module declares configuration_aliases [aws.management]; declaring a second
# mock_provider with that alias satisfies it automatically in `terraform test`.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

variables {
  security_tooling_account_id = "111111111111"
  org_root_id                 = "r-abc1"
}

run "central_configuration_with_standards" {
  command = plan

  assert {
    condition     = aws_securityhub_organization_configuration.this.organization_configuration[0].configuration_type == "CENTRAL"
    error_message = "Organization configuration must use the CENTRAL configuration type"
  }

  assert {
    condition     = aws_securityhub_organization_configuration.this.auto_enable == false && aws_securityhub_organization_configuration.this.auto_enable_standards == "NONE"
    error_message = "CENTRAL configuration requires auto_enable = false and auto_enable_standards = NONE"
  }

  assert {
    condition     = length(aws_securityhub_configuration_policy.baseline.configuration_policy[0].enabled_standard_arns) > 0
    error_message = "Baseline configuration policy must enable at least one security standard"
  }

  assert {
    condition     = aws_securityhub_finding_aggregator.this.linking_mode == "ALL_REGIONS"
    error_message = "Finding aggregator must link ALL_REGIONS (CENTRAL prerequisite)"
  }
}
