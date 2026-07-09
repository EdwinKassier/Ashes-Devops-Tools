# Basic working example for the aws/edge-security module.
#
# CloudFront's WAF and ACM dependencies are global and must live in us-east-1,
# so the root declares a us-east-1 aliased provider and passes it to the module
# as aws.us_east_1. The default provider is the workload's home Region. Run
# `terraform init && terraform validate` here to check it.

# Default provider — the workload's home Region.
provider "aws" {
  region = "eu-west-2"
}

# Aliased provider — us-east-1, required for CloudFront-scoped WAF and ACM.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "edge_security" {
  source = "../../"

  enable_edge        = true
  name_prefix        = "example"
  origin_domain_name = "origin.example.com"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
