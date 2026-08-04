# Aliased-provider reference pattern (cross-account / multi-region).
#
# When a module must create resources in a DIFFERENT account or region than the
# root's default provider, the ROOT declares an aliased aws provider and passes
# it explicitly into the module via a `providers = { aws = aws.member }` map.
# The module itself declares `configuration_aliases = [aws.member]` in its
# required_providers — that is intentionally omitted from the scaffold module so
# the default single-provider case stays simple. This example shows only the
# root-side wiring so `terraform validate` accepts it with no downstream module.

# Default provider — the "management" / home account.
provider "aws" {
  region = "eu-west-1"
}

# Aliased provider — assume a role in the member account / target region. In a
# real root this uses assume_role; kept minimal here so the example validates.
provider "aws" {
  alias  = "member"
  region = "us-east-1"
}

# Example of passing the aliased provider into a module (commented — the
# scaffold module does not declare configuration_aliases, so wiring it here
# would fail validation). Copy this shape into a real root that consumes a
# cross-account module:
#
# module "member_scoped" {
#   source = "../../modules/MODULE_NAME"
#
#   name = "cross-account-param"
#
#   providers = {
#     aws = aws.member
#   }
# }
