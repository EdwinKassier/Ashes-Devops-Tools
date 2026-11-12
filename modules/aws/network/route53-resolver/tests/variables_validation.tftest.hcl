# Variable validation tests for the aws/route53-resolver module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # Required inputs plus defaults must pass validation.
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }
}

run "empty_vpc_id_rejected" {
  # An empty vpc_id must trip the non-empty validation.
  command = plan

  variables {
    vpc_id                    = ""
    org_arn                   = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }

  expect_failures = [var.vpc_id]
}

run "query_logging_enabled_without_destination_rejected" {
  # Enabling query logging with an empty destination arn ships logs nowhere
  # and must trip the validation.
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
    enable_query_logging      = true
    query_log_destination_arn = ""
  }

  expect_failures = [var.query_log_destination_arn]
}

run "forward_rules_need_endpoints" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    forward_rules             = { corp = { domain_name = "corp.example.", target_ips = ["192.168.0.10"] } }
  }

  expect_failures = [var.forward_rules]
}

run "enabled_endpoints_need_two_subnets" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    enable_resolver_endpoints = true
    subnet_ids                = ["subnet-0a"]
    allowed_cidrs             = ["10.64.0.0/10"]
  }

  expect_failures = [var.subnet_ids]
}

run "enabled_endpoints_need_a_source" {
  # A module-owned group with no allowed_cidrs would admit nothing.
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    enable_resolver_endpoints = true
    subnet_ids                = ["subnet-0a", "subnet-0b"]
  }

  expect_failures = [var.allowed_cidrs]
}

run "allowed_cidrs_must_be_cidrs" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    allowed_cidrs             = ["not-a-cidr"]
  }

  expect_failures = [var.allowed_cidrs]
}
