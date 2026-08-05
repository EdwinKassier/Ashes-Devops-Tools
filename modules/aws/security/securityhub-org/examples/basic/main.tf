# Basic working example for the aws/securityhub-org module.
#
# The module spans two accounts, so the root wires two providers: the default
# provider is the delegated-administrator (Security Tooling) account, and the
# aliased `aws.management` provider is the organization management account (which
# owns the delegated-admin registration). Run `terraform init && terraform
# validate` here to check it.

# Default provider — the delegated-administrator (Security Tooling) account.
provider "aws" {
  region = "eu-west-2"
}

# Aliased provider — the organization management account. In a real root this
# assumes a role in the management account; kept minimal here so the example
# validates.
provider "aws" {
  alias  = "management"
  region = "eu-west-2"
}

module "securityhub_org" {
  source = "../../"

  security_tooling_account_id = "111111111111"
  org_root_id                 = "r-abcd"
  home_region                 = "eu-west-2"

  providers = {
    aws            = aws
    aws.management = aws.management
  }
}
