# Phase-3 per-env workload root. BOTH providers authenticate into the SAME per-env
# workload account (local.workload_account_key) — via the workspace's TFC dynamic
# credentials for that account's tfc-plan / tfc-apply role, or, for legacy runs,
# by assuming var.assume_role_arn. The default provider operates in the workload's home
# region; the us_east_1 alias operates in us-east-1 (same account) for the
# optional edge-security module's CloudFront/WAF/ACM resources.
#
# Declares ONLY the aws provider — no supabase/vercel (SaaS lives in envs/saas).
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
  # account_role_arns[local.workload_account_key] (OrganizationAccountAccessRole).
  dynamic "assume_role" {
    for_each = var.assume_role_arn == null ? [] : [var.assume_role_arn]
    content {
      role_arn = assume_role.value
    }
  }
  # Fail fast if the resolved credentials are not the target member account
  # (local.workload_account_id: organization contract or remote state, main.tf).
  allowed_account_ids = [local.workload_account_id]
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = local.aws_default_tags
  }
  # Credential model: by default (assume_role_arn = null) the run's TFC dynamic
  # credentials ARE the member account's tfc-plan / tfc-apply role (created by
  # the aws-organization TFC OIDC baseline), so no role hop happens and no
  # management-account principal is involved. Legacy/local runs that start from
  # management-account credentials set assume_role_arn to
  # account_role_arns[local.workload_account_key] (OrganizationAccountAccessRole).
  dynamic "assume_role" {
    for_each = var.assume_role_arn == null ? [] : [var.assume_role_arn]
    content {
      role_arn = assume_role.value
    }
  }
  # Fail fast if the resolved credentials are not the target member account
  # (local.workload_account_id: organization contract or remote state, main.tf).
  allowed_account_ids = [local.workload_account_id]
}

# Canonical tag set written by EVERY aws provider in this root (default_tags).
# Keys match the org tag policy + the cost-governance cost-allocation tags
# (CostCenter, Environment, Owner) so the activated tags are actually populated.
# Values are plan-known, non-empty strings: a computed or empty default tag
# would make the provider plan a perpetual diff. Module-level `tags` only ADD
# keys (Name, Tier, ...), so the two never fight.
locals {
  # Environment for tags + naming: explicit var.environment, else derived from
  # workload_account_key (workload_dev -> dev).
  environment = coalesce(var.environment, trimprefix(trimprefix(local.workload_account_key, "workload_"), "workload-"))

  aws_default_tags = merge(
    {
      ManagedBy   = "terraform"
      LandingZone = local.landing_zone_name
      Workspace   = "aws-workload-${local.environment}"
      Environment = local.environment
      CostCenter  = local.cost_center
      Owner       = local.owner
    },
    var.default_tags,
  )
}

# tfe serves only the opt-in SaaS secret bridge (ephemeral "tfe_outputs" "saas").
# Terraform configures a declared provider even when nothing uses it, and tfe
# refuses to configure without a token, so a workspace with the bridge off gets
# an inert placeholder (NOT a secret, and it grants nothing: on configure the
# provider only calls the host's discovery and ping endpoints, which need no
# valid token). With the bridge on, token = null reads TFE_TOKEN: the
# saas-outputs-reader team token.
provider "tfe" {
  token = var.enable_saas_secret_bridge ? null : "saas-bridge-disabled-placeholder"
}
