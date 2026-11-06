# Phase-2 backup root. This root spans two accounts. The DEFAULT provider
# authenticates as / into the MANAGEMENT (payer) account — that is where the
# org-owned resource lives (the organization BACKUP_POLICY attached to the
# Workloads OU). The default provider is therefore ALSO wired to the stage's
# default (aws) provider in main.tf. The backup account is reached through the
# TFC "backup" dynamic-credential alias (its tfc-plan / tfc-apply role, no role
# chaining) or, for local / legacy runs, by assuming account_role_arns["backup"].
provider "aws" {
  region = local.aws_region
  default_tags {
    tags = local.aws_default_tags
  }
  # C4: fail fast if the resolved credentials are not the management (payer)
  # account. The default provider owns the org BACKUP_POLICY; the backup account
  # is reached via the aliased assume-role provider below.
  allowed_account_ids = [local.management_account_id]
  # TFC multi-configuration dynamic credentials (see var.tfc_aws_dynamic_credentials):
  # the default config is the management-account role this workspace runs as.
  shared_config_files = var.tfc_aws_dynamic_credentials == null ? null : [var.tfc_aws_dynamic_credentials.default.shared_config_file]
}

provider "aws" {
  alias  = "backup"
  region = local.aws_region
  default_tags {
    tags = local.aws_default_tags
  }
  # Under TFC, the "backup" dynamic-credential alias authenticates DIRECTLY as
  # that account's tfc-plan / tfc-apply role (TFC_AWS_*_backup env vars) — no
  # management-account role chaining. Without it (local / legacy), fall back to
  # assuming account_role_arns["backup"] (OrganizationAccountAccessRole).
  shared_config_files = var.tfc_aws_dynamic_credentials == null ? null : [var.tfc_aws_dynamic_credentials.aliases["backup"].shared_config_file]
  dynamic "assume_role" {
    for_each = var.tfc_aws_dynamic_credentials == null ? [local.org.account_role_arns["backup"]] : []
    content {
      role_arn = assume_role.value
    }
  }
  # No try(): a missing account_ids key fails the plan loudly instead of
  # silently dropping the wrong-account guard.
  allowed_account_ids = [local.org.account_ids["backup"]]
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
      Workspace   = "aws-backup"
      Environment = "shared"
      CostCenter  = local.cost_center
      Owner       = local.owner
    },
    var.default_tags,
  )
}
