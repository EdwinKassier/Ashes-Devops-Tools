# Variable validation tests for the aws/network-firewall module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

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
