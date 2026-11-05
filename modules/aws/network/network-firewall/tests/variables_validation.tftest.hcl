# Variable validation tests for the aws/network-firewall module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {
  # Valid region so the AWS-managed rule group ARNs pass provider validation.
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
}

run "defaults_accepted" {
  # Defaults plus the required inspection_vpc_id and log_bucket_name must pass.
  command = plan

  variables {
    inspection_vpc_id = "vpc-inspection0000000"
    log_bucket_name   = "example-firewall-log-bucket"
  }
}

run "zero_capacity_rejected" {
  # rule_group_capacity below 1 must trip validation.
  command = plan

  variables {
    inspection_vpc_id   = "vpc-inspection0000000"
    log_bucket_name     = "example-firewall-log-bucket"
    rule_group_capacity = 0
  }

  expect_failures = [var.rule_group_capacity]
}

run "action_order_managed_group_rejected" {
  # Strict-order policies can only attach StrictOrder managed groups.
  command = plan

  variables {
    inspection_vpc_id   = "vpc-inspection0000000"
    log_bucket_name     = "example-firewall-log-bucket"
    managed_rule_groups = ["MalwareDomainsActionOrder"]
  }

  expect_failures = [var.managed_rule_groups]
}

run "two_drop_default_actions_rejected" {
  command = plan

  variables {
    inspection_vpc_id        = "vpc-inspection0000000"
    log_bucket_name          = "example-firewall-log-bucket"
    stateful_default_actions = ["aws:drop_strict", "aws:drop_established"]
  }

  expect_failures = [var.stateful_default_actions]
}

run "invalid_home_net_rejected" {
  command = plan

  variables {
    inspection_vpc_id = "vpc-inspection0000000"
    log_bucket_name   = "example-firewall-log-bucket"
    home_net_cidrs    = ["not-a-cidr"]
  }

  expect_failures = [var.home_net_cidrs]
}
