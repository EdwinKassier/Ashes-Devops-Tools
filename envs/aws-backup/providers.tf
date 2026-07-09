# Phase-2 backup root. This root spans two accounts. The DEFAULT provider
# authenticates as / into the MANAGEMENT (payer) account — that is where the
# org-owned resource lives (the organization BACKUP_POLICY attached to the
# Workloads OU). The default provider is therefore ALSO wired to the stage's
# default (aws) provider in main.tf. The backup account is reached by assuming
# the cross-account access role ARN published by the aws-organization root's
# remote state.
provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "backup"
  region = var.aws_region
  assume_role {
    role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["backup"]
  }
}
