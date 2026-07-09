# Basic working example for the aws/transit-gateway module.
# Uses the module defaults (prod/nonprod/inspection/shared segments, one
# attachment each, prod<->nonprod isolated) and supplies the required org_arn.
# Run `terraform init && terraform validate` here to check it.

module "transit_gateway" {
  source = "../../"

  org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
}
