# A workload root has ONE default provider. The region comes from local.aws_region
# (variable > config file > eu-west-2, see config.tf) so
# the same root can be pointed at any region without code edits.
provider "aws" {
  region = local.aws_region
  default_tags {
    tags = local.aws_default_tags
  }
}

# Canonical tag set written by EVERY aws provider in this root (default_tags),
# as in envs/aws/network/providers.tf. The OPA policy require_labels
# (mandatory) denies a listed resource without ManagedBy, Environment,
# CostCenter and Owner. DataClassification is the tag policy's data-sensitivity
# key (public, internal, confidential, restricted): set it for the data this
# layer holds. Values must be plan-known, non-empty strings: a computed or empty
# default tag makes the provider plan a perpetual diff.
locals {
  aws_default_tags = {
    ManagedBy          = "terraform"
    Workspace          = "aws-<layer>" # the workspace name from backend.tf
    Environment        = "shared"
    CostCenter         = local.cost_center # org.cost_center, else "platform"
    Owner              = local.owner       # org.owner, else "platform-team"
    DataClassification = "internal"
  }
}

# Cross-account roots add one aliased provider PER FIXED FOUNDATIONAL ACCOUNT
# (never per workload — workloads fan out by workspace). Role ARNs come from
# the aws-organization remote state (two-phase bootstrap), known at plan time.
# provider "aws" {
#   alias  = "security_tooling"
#   region = local.aws_region
#   default_tags {
#     tags = local.aws_default_tags
#   }
#   assume_role { role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["security_tooling"] }
# }
