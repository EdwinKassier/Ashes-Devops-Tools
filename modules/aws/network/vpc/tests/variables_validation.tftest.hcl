# Variable validation tests for the aws/vpc module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # Defaults plus the required flow_log_destination_arn must pass validation.
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }
}

run "bad_cidr_block_rejected" {
  # A malformed cidr_block must trip the cidrnetmask-based validation.
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    cidr_block               = "not-a-cidr"
  }

  expect_failures = [var.cidr_block]
}

run "route_with_two_targets_rejected" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    routes = {
      private = [{ destination_cidr_block = "0.0.0.0/0", transit_gateway_id = "tgw-1", nat_gateway_id = "nat-1" }]
    }
  }

  expect_failures = [var.routes]
}

run "route_for_unknown_tier_rejected" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    routes = {
      nosuchtier = [{ destination_cidr_block = "0.0.0.0/0", transit_gateway_id = "tgw-1" }]
    }
  }

  expect_failures = [var.routes]
}
