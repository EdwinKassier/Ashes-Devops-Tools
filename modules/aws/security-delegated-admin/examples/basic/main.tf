# Basic working example for the aws/security-delegated-admin module.
#
# This module runs entirely from the organization MANAGEMENT account, so the
# root needs only a single default provider (no aliased provider). Run
# `terraform init && terraform validate` here to check it.

# Default provider — the organization management account.
provider "aws" {
  region = "eu-west-2"
}

module "security_delegated_admin" {
  source = "../../"

  security_tooling_account_id = "111111111111"
  identity_account_id         = "222222222222"

  providers = {
    aws = aws
  }
}
