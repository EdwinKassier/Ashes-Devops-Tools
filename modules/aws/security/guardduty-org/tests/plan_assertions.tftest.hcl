# Resource-assertion tests for the aws/guardduty-org module.
#
# Asserts on configured attributes and for_each materialization, which are known
# at plan time under mock_provider. The module declares a configuration_aliases
# [aws.management]; declaring a second mock_provider with that alias satisfies it
# automatically in `terraform test`.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

variables {
  security_tooling_account_id = "111111111111"
  aws_enabled_regions         = ["eu-west-2"]
}

run "org_configuration_auto_enables_all" {
  command = plan

  assert {
    condition     = aws_guardduty_organization_configuration.this["eu-west-2"].auto_enable_organization_members == "ALL"
    error_message = "Org configuration must auto-enable all organization members"
  }

  # Non-vacuous: prove the RUNTIME_MONITORING feature is materialized per Region.
  assert {
    condition     = contains(keys(aws_guardduty_organization_configuration_feature.this), "eu-west-2:RUNTIME_MONITORING")
    error_message = "RUNTIME_MONITORING feature must be materialized for each enabled Region"
  }
}

# Runtime Monitoring must manage its agents, or it is billed but blind.
run "runtime_monitoring_manages_agents" {
  command = plan

  assert {
    condition = toset([
      for c in aws_guardduty_organization_configuration_feature.this["eu-west-2:RUNTIME_MONITORING"].additional_configuration : c.name if c.auto_enable == "ALL"
    ]) == toset(["ECS_FARGATE_AGENT_MANAGEMENT", "EKS_ADDON_MANAGEMENT", "EC2_AGENT_MANAGEMENT"])
    error_message = "RUNTIME_MONITORING must auto-enable Fargate, EKS and EC2 agent management for all members."
  }

  assert {
    condition     = length(aws_guardduty_organization_configuration_feature.this["eu-west-2:S3_DATA_EVENTS"].additional_configuration) == 0
    error_message = "agent management belongs only on RUNTIME_MONITORING."
  }
}
