# Basic working example for the aws/firewall-manager-org module.
#
# The module spans two accounts: the default provider is the FMS administrator
# (Security Tooling) account that owns the policies, and the aliased
# `aws.management` provider is the organization management account that owns the
# FMS admin-account registration. Run `terraform init && terraform validate`
# here to check it.

# Default provider — the FMS administrator (Security Tooling) account.
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

module "firewall_manager_org" {
  source = "../../"

  fms_admin_account_id = "111111111111"

  providers = {
    aws            = aws
    aws.management = aws.management
  }
}
