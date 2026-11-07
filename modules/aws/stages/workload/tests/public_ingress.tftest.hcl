# Plan assertions for the optional public ingress tier (enable_public_subnets)
# and the route-less internet gateway (create_internet_gateway) the aws-workload
# root turns on for app_ingress_mode = "public_alb" / "cloudfront_vpc_origin".
# command = apply (mocked) so the internet gateway id is concrete.

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }

variables {
  flow_log_destination_arn = "arn:aws:s3:::acme-org-log-archive"
  log_archive_bucket_name  = "acme-org-log-archive"
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
  # SSM is orthogonal here; its patch-baseline id fails provider validation
  # under apply with random mock values.
  enable_ssm = false
}

run "default_has_no_public_tier_or_igw" {
  command = apply

  assert {
    condition     = !contains(keys(output.subnet_ids_by_tier), "public")
    error_message = "No public subnets by default"
  }

  assert {
    condition     = output.internet_gateway_id == null
    error_message = "No internet gateway by default"
  }
}

run "public_subnets_add_tier_and_igw" {
  command = apply

  variables {
    enable_public_subnets = true
  }

  assert {
    condition     = length(output.subnet_ids_by_tier["public"]) == 2
    error_message = "enable_public_subnets must add one public subnet per AZ"
  }

  assert {
    condition     = output.internet_gateway_id != null
    error_message = "The public tier needs an internet gateway"
  }

  assert {
    condition     = length(output.subnet_ids_by_tier["private"]) == 2 && length(output.subnet_ids_by_tier["tgw"]) == 2
    error_message = "The private/isolated/tgw tiers are unchanged"
  }
}

run "igw_without_public_subnets" {
  command = apply

  variables {
    create_internet_gateway = true
  }

  assert {
    condition     = output.internet_gateway_id != null && !contains(keys(output.subnet_ids_by_tier), "public")
    error_message = "create_internet_gateway alone attaches an IGW without a public tier"
  }
}

# A CMK created in the caller's plan (unknown ARN) must not feed a for_each:
# enable_ebs_default_kms_key = true sets the home-region default key via count.
run "stage_owned_ebs_default_key" {
  command = apply

  variables {
    enable_ebs_default_kms_key = true
  }

  assert {
    condition     = length(aws_ebs_default_kms_key.home) == 1 && aws_ebs_default_kms_key.home[0].key_arn == var.kms_key_arn
    error_message = "enable_ebs_default_kms_key = true must set the home-region default EBS key"
  }
}

# The org declarative EC2 policy blocks IGW ingress (VPC BPA) on every VPC: no
# exclusion by default, and a VPC-scoped allow-bidirectional one on request.
run "no_bpa_exclusion_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpc_block_public_access_exclusion.public_ingress) == 0
    error_message = "no VPC BPA exclusion may exist unless explicitly requested"
  }
}

run "bpa_exclusion_scoped_to_spoke_vpc" {
  command = plan

  variables {
    enable_public_subnets    = true
    enable_vpc_bpa_exclusion = true
  }

  assert {
    condition     = length(aws_vpc_block_public_access_exclusion.public_ingress) == 1 && aws_vpc_block_public_access_exclusion.public_ingress[0].internet_gateway_exclusion_mode == "allow-bidirectional" && aws_vpc_block_public_access_exclusion.public_ingress[0].subnet_id == null
    error_message = "the exclusion must be allow-bidirectional and scoped to the VPC (not a subnet)"
  }
}
