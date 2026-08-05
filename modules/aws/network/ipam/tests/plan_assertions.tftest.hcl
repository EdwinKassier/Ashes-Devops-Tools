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
