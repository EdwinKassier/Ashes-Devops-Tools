# Resource-assertion tests for the aws/vpc module.
#
# Asserts on configured attributes and on for_each-derived counts that are
# known at plan time under mock_provider. Provider-computed attributes (ids,
# arns) are not asserted on.

mock_provider "aws" {}

run "vpc_and_subnets_configured" {
  command = plan

  variables {
    region                   = "eu-west-2"
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "VPC must enable DNS hostnames."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true
    error_message = "VPC must enable DNS support."
  }

  # Non-vacuous: with defaults az_count=2 and 3 tiers, 2 * 3 = 6 subnets.
  assert {
    condition     = length(aws_subnet.this) == var.az_count * length(keys(var.subnets))
    error_message = "One subnet must be created per tier per AZ (az_count * tier count)."
  }

  assert {
    condition     = length(aws_subnet.this) == 6
    error_message = "Defaults must produce exactly 6 subnets (2 AZs x 3 tiers)."
  }

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "Flow log must capture ALL traffic."
  }

  assert {
    condition     = length(aws_vpc_endpoint.gateway) == 2
    error_message = "Default gateway endpoints (s3, dynamodb) must both be created."
  }
}
