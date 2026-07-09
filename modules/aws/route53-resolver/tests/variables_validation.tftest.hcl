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
