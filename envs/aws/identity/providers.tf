# Phase-2 identity root. A SINGLE default provider that authenticates into the
# SHARED SERVICES account via the workspace's TFC
# dynamic credentials for that account's tfc-plan / tfc-apply role (legacy runs:
# by assuming var.assume_role_arn). IAM Identity Center
# permission sets and assignments are delegated-administered from there (the
# instance itself is enabled out-of-band in the management account).
provider "aws" {
  region = local.aws_region
  default_tags {
    tags = local.aws_default_tags
  }
  # Credential model: by default (assume_role_arn = null) the run's TFC dynamic
  # credentials ARE the member account's tfc-plan / tfc-apply role (created by
  # the aws-organization TFC OIDC baseline), so no role hop happens and no
  # management-account principal is involved. Legacy/local runs that start from
  # management-account credentials set assume_role_arn to
  # account_role_arns[shared_services] (OrganizationAccountAccessRole).
  dynamic "assume_role" {
    for_each = var.assume_role_arn == null ? [] : [var.assume_role_arn]
    content {
      role_arn = assume_role.value
    }
  }
  # Fail fast if the resolved credentials are not the target member account.
  # No try(): a missing account_ids key fails the plan loudly instead of
  # silently dropping the wrong-account guard.
  allowed_account_ids = [local.org.account_ids["shared_services"]]
}

# Canonical tag set written by EVERY aws provider in this root (default_tags).
# Keys match the org tag policy + the cost-governance cost-allocation tags
# (CostCenter, Environment, Owner) so the activated tags are actually populated.
# Values are plan-known, non-empty strings: a computed or empty default tag
# would make the provider plan a perpetual diff. Module-level `tags` only ADD
# keys (Name, Tier, ...), so the two never fight.
locals {
  aws_default_tags = merge(
    {
      ManagedBy   = "terraform"
      LandingZone = local.landing_zone_name
      Workspace   = "aws-identity"
      Environment = "shared"
      CostCenter  = local.cost_center
      Owner       = local.owner
    },
    var.default_tags,
  )
}
