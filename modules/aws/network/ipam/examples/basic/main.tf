# Basic working example for the aws/ipam module.
# Uses the module defaults (single eu-west-2 region, 10.0.0.0/8 supernet) and
# supplies the required organization ARN. Run `terraform init &&
# terraform validate` here to check it.

module "ipam" {
  source = "../../"

  org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
}
