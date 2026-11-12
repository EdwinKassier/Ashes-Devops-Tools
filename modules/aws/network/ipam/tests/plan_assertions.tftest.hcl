# Resource-assertion tests for the aws/ipam module.
#
# Asserts on configured attributes that are known at plan time under
# mock_provider. Provider-computed attributes (ids, arns) are not asserted on.

mock_provider "aws" {}

run "ipam_pools_configured" {
  command = plan

  variables {
    org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
  }

  assert {
    condition     = aws_vpc_ipam_pool.top.address_family == "ipv4"
    error_message = "Top pool must use the ipv4 address family."
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.top.cidr == "10.0.0.0/8"
    error_message = "Top pool CIDR must equal the default top_cidr (10.0.0.0/8)."
  }

  assert {
    condition     = aws_vpc_ipam_pool.top.locale == null
    error_message = "Top pool must have no locale."
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional["eu-west-2"].locale == "eu-west-2"
    error_message = "Regional pool locale must match its region key."
  }

  assert {
    condition     = aws_ram_resource_share.this.allow_external_principals == false
    error_message = "RAM share must not allow external principals."
  }
}

run "module_tags_applied" {
  command = plan

  variables {
    org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
    tags    = { Owner = "test" }
  }

  assert {
    condition     = aws_vpc_ipam.this.tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_vpc_ipam.this"
  }
}

run "regional_pool_can_grow_and_share_narrowly" {
  command = plan

  variables {
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    aws_enabled_regions       = ["eu-west-2"]
    top_cidr                  = "10.64.0.0/10"
    regional_cidrs            = { eu-west-2 = "10.64.0.0/12" }
    regional_additional_cidrs = { eu-west-2 = ["10.80.0.0/12"] }
    share_principal_arns      = ["arn:aws:organizations::111111111111:ou/o-abc1234567/ou-ab12-workload1"]
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional_additional["eu-west-2|10.80.0.0/12"].cidr == "10.80.0.0/12"
    error_message = "A region must be able to provision a second CIDR when its first /12 is full (14 workloads at /16)."
  }

  assert {
    condition     = length(aws_ram_principal_association.org) == 0 && keys(aws_ram_principal_association.this) == ["arn:aws:organizations::111111111111:ou/o-abc1234567/ou-ab12-workload1"]
    error_message = "The pools must be shareable to named OUs only, so accounts outside them cannot drain the pool."
  }
}

run "default_share_stays_org_wide" {
  command = plan

  variables {
    org_arn = "arn:aws:organizations::111111111111:organization/o-abc1234567"
  }

  assert {
    condition     = length(aws_ram_principal_association.org) == 1 && aws_ram_principal_association.org[0].principal == "arn:aws:organizations::111111111111:organization/o-abc1234567" && length(aws_ram_principal_association.this) == 0
    error_message = "With no share_principal_arns the share keeps the org principal at aws_ram_principal_association.org[0] (moved from the un-indexed address)."
  }

  assert {
    condition     = length(aws_vpc_ipam_pool_cidr.regional_additional) == 0
    error_message = "With no regional_additional_cidrs no extra pool CIDR is provisioned."
  }
}
