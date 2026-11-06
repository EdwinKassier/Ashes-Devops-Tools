# Phase-2 security root. Unlike phase-1 (single default provider), this root spans
# four accounts. The DEFAULT provider authenticates as / into the MANAGEMENT
# (payer) account — that is where the org-owned resources live (org CloudTrail,
# delegated-administrator registrations). The default provider is therefore ALSO
# wired to the stage's aws.management alias in main.tf. The other three accounts
# are reached through TFC multi-configuration dynamic credentials — one alias per
# account, each authenticating DIRECTLY as that account's tfc-plan / tfc-apply
# role — or, for local / legacy runs, by assuming account_role_arns (OAAR).
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.aws_default_tags
  }
  # C4: fail fast if the resolved credentials are not the management (payer)
  # account. The default provider owns org-level resources (org CloudTrail,
  # delegated-admin registrations); the other accounts are reached via the
  # aliased assume-role providers below.
  allowed_account_ids = [var.management_account_id]
  # TFC multi-configuration dynamic credentials (see var.tfc_aws_dynamic_credentials):
  # the default config is the management-account role this workspace runs as.
  shared_config_files = var.tfc_aws_dynamic_credentials == null ? null : [var.tfc_aws_dynamic_credentials.default.shared_config_file]
}

provider "aws" {
  alias  = "security_tooling"
  region = var.aws_region
  default_tags {
    tags = local.aws_default_tags
  }
  # Under TFC, the "security_tooling" dynamic-credential alias authenticates DIRECTLY as
  # that account's tfc-plan / tfc-apply role (TFC_AWS_*_security_tooling env vars) — no
  # management-account role chaining. Without it (local / legacy), fall back to
  # assuming account_role_arns["security_tooling"] (OrganizationAccountAccessRole).
  shared_config_files = var.tfc_aws_dynamic_credentials == null ? null : [var.tfc_aws_dynamic_credentials.aliases["security_tooling"].shared_config_file]
  dynamic "assume_role" {
    for_each = var.tfc_aws_dynamic_credentials == null ? [data.terraform_remote_state.aws_organization.outputs.account_role_arns["security_tooling"]] : []
    content {
      role_arn = assume_role.value
    }
  }
  # No try(): a missing account_ids key fails the plan loudly instead of
  # silently dropping the wrong-account guard.
  allowed_account_ids = [data.terraform_remote_state.aws_organization.outputs.account_ids["security_tooling"]]
}

provider "aws" {
  alias  = "log_archive"
  region = var.aws_region
  default_tags {
    tags = local.aws_default_tags
  }
  # Under TFC, the "log_archive" dynamic-credential alias authenticates DIRECTLY as
  # that account's tfc-plan / tfc-apply role (TFC_AWS_*_log_archive env vars) — no
  # management-account role chaining. Without it (local / legacy), fall back to
  # assuming account_role_arns["log_archive"] (OrganizationAccountAccessRole).
  shared_config_files = var.tfc_aws_dynamic_credentials == null ? null : [var.tfc_aws_dynamic_credentials.aliases["log_archive"].shared_config_file]
  dynamic "assume_role" {
    for_each = var.tfc_aws_dynamic_credentials == null ? [data.terraform_remote_state.aws_organization.outputs.account_role_arns["log_archive"]] : []
    content {
      role_arn = assume_role.value
    }
  }
  # No try(): a missing account_ids key fails the plan loudly instead of
  # silently dropping the wrong-account guard.
  allowed_account_ids = [data.terraform_remote_state.aws_organization.outputs.account_ids["log_archive"]]
}

provider "aws" {
  alias  = "forensics"
  region = var.aws_region
  default_tags {
    tags = local.aws_default_tags
  }
  # Under TFC, the "forensics" dynamic-credential alias authenticates DIRECTLY as
  # that account's tfc-plan / tfc-apply role (TFC_AWS_*_forensics env vars) — no
  # management-account role chaining. Without it (local / legacy), fall back to
  # assuming account_role_arns["forensics"] (OrganizationAccountAccessRole).
  shared_config_files = var.tfc_aws_dynamic_credentials == null ? null : [var.tfc_aws_dynamic_credentials.aliases["forensics"].shared_config_file]
  dynamic "assume_role" {
    for_each = var.tfc_aws_dynamic_credentials == null ? [data.terraform_remote_state.aws_organization.outputs.account_role_arns["forensics"]] : []
    content {
      role_arn = assume_role.value
    }
  }
  # No try(): a missing account_ids key fails the plan loudly instead of
  # silently dropping the wrong-account guard.
  allowed_account_ids = [data.terraform_remote_state.aws_organization.outputs.account_ids["forensics"]]
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
      Workspace   = "aws-security"
      Environment = "shared"
      CostCenter  = var.cost_center
      Owner       = var.owner
    },
    var.default_tags,
  )
}
