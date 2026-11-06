# Phase-1 foundation root. The organization, guardrails (SCP/RCP/declarative/tag),
# foundational account vending, and centralized root-access management all run in
# the MANAGEMENT (payer) account, so this root has a SINGLE default provider and
# NO aliased providers. Region comes from local.aws_region so the same root can be
# pointed at any region without code edits.
provider "aws" {
  region = local.aws_region
  default_tags {
    tags = local.aws_default_tags
  }
  # Fail fast if the resolved credentials are not the management (payer)
  # account. This root creates org-level resources (org, SCPs, account factory);
  # a mis-set AWS_PROFILE or TFC run role must never deploy them into the wrong
  # account. Admins set management_account_id to their own payer account.
  allowed_account_ids = [local.management_account_id]
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
      Workspace   = "aws-organization"
      Environment = "shared"
      CostCenter  = local.cost_center
      Owner       = local.owner
    },
    var.default_tags,
  )
}
