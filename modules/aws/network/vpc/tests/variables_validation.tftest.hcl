# Variable validation tests for the aws/vpc module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

# region is required (no hard-coded default); runs may override it.
variables {
  region = "eu-west-2"
}

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

run "availability_zones_from_another_region_rejected" {
  command = plan

  variables {
    region                   = "us-east-1"
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }

  # The default availability_zones are eu-west-2a/b/c.
  expect_failures = [aws_vpc.this]
}

run "availability_zones_in_region_accepted" {
  command = plan

  variables {
    region                   = "us-east-1"
    availability_zones       = ["us-east-1a", "us-east-1b"]
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }

  assert {
    condition     = output.availability_zones == tolist(["us-east-1a", "us-east-1b"])
    error_message = "The module must expose the availability zones it placed subnets in."
  }
}

# The flow-log destination accepts the GovCloud and European Sovereign Cloud
# partitions and rejects an unknown one. The region stays eu-west-2: only the
# ARN is under test here.
run "accepts_eusc_flow_log_arn" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws-eusc:s3:::example-log-archive-bucket"
  }

  assert {
    condition     = var.flow_log_destination_arn == "arn:aws-eusc:s3:::example-log-archive-bucket"
    error_message = "an aws-eusc S3 ARN must pass the flow-log destination validation."
  }
}

run "accepts_govcloud_flow_log_arn" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws-us-gov:s3:::example-log-archive-bucket"
  }

  assert {
    condition     = var.flow_log_destination_arn == "arn:aws-us-gov:s3:::example-log-archive-bucket"
    error_message = "an aws-us-gov S3 ARN must pass the flow-log destination validation."
  }
}

run "rejects_unknown_partition_flow_log_arn" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws-iso-x:s3:::example-log-archive-bucket"
  }

  expect_failures = [var.flow_log_destination_arn]
}

run "gateway_endpoint_policy_for_absent_endpoint_rejected" {
  command = plan

  variables {
    flow_log_destination_arn  = "arn:aws:s3:::example-log-archive-bucket"
    gateway_endpoints         = ["s3"]
    gateway_endpoint_policies = { dynamodb = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  expect_failures = [var.gateway_endpoint_policies]
}

run "gateway_endpoint_policy_must_be_json" {
  command = plan

  variables {
    flow_log_destination_arn  = "arn:aws:s3:::example-log-archive-bucket"
    gateway_endpoint_policies = { s3 = "not json" }
  }

  expect_failures = [var.gateway_endpoint_policies]
}
