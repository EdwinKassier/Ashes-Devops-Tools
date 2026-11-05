# Phase-2 shared-services root. A SINGLE default provider that authenticates into
# the SHARED SERVICES account via the workspace's TFC
# dynamic credentials for that account's tfc-plan / tfc-apply role (legacy runs:
# by assuming var.assume_role_arn). All shared-services
# resources (ACM Private CA, Secrets Manager baseline) live in that one account.
provider "aws" {
  region = var.aws_region
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
  allowed_account_ids = try([data.terraform_remote_state.aws_organization.outputs.account_ids["shared_services"]], null)
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
      LandingZone = var.landing_zone_name
      Workspace   = "aws-shared-services"
      Environment = "shared"
      CostCenter  = var.cost_center
      Owner       = var.owner
    },
    var.default_tags,
  )
}
