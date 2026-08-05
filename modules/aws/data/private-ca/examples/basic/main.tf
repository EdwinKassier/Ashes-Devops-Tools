# Basic working example for the aws/private-ca module.
# Enables the CA and shares it across the organization. Run
# `terraform init && terraform validate` here to check it.

module "private_ca" {
  source = "../../"

  enable_private_ca = true
  common_name       = "example-internal-ca"
  org_arn           = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
}
