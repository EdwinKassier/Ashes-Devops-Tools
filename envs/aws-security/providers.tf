# Phase-2 security root. Unlike phase-1 (single default provider), this root spans
# four accounts. The DEFAULT provider authenticates as / into the MANAGEMENT
# (payer) account — that is where the org-owned resources live (org CloudTrail,
# delegated-administrator registrations). The default provider is therefore ALSO
# wired to the stage's aws.management alias in main.tf. The other three accounts
# are reached by assuming the cross-account access role ARNs published by the
# aws-organization root's remote state.
provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "security_tooling"
  region = var.aws_region
  assume_role {
    role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["security_tooling"]
  }
}

provider "aws" {
  alias  = "log_archive"
  region = var.aws_region
  assume_role {
    role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["log_archive"]
  }
}

provider "aws" {
  alias  = "forensics"
  region = var.aws_region
  assume_role {
    role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["forensics"]
  }
}
