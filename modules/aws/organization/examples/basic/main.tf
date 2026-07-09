# Basic working example for the aws/organization module.
# Uses the module defaults (full SRA OU tree). Run `terraform init &&
# terraform validate` here to check it.

module "organization" {
  source = "../../"
}
