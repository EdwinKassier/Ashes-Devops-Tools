# Variable validation tests for the aws/transit-gateway module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # Defaults plus the required org_arn must pass validation.
  command = plan

  variables {
    org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
  }
}

run "bad_org_arn_rejected" {
  # A non-Organizations ARN must trip the org_arn validation.
  command = plan

  variables {
    org_arn = "arn:aws:iam::123456789012:root"
  }

  expect_failures = [var.org_arn]
}

run "attachment_segment_not_in_route_tables_rejected" {
  # An attachment whose segment is not a declared route table must be rejected.
  command = plan

  variables {
    org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
    attachments = {
      rogue = {
        vpc_id     = "vpc-rogue0000000000"
        subnet_ids = ["subnet-rogue0a"]
        segment    = "does-not-exist"
      }
    }
    propagations = {}
    routes       = {}
  }

  expect_failures = [var.attachments]
}
