# Phase-2 identity root. A SINGLE default provider that authenticates into the
# SHARED SERVICES account by assuming the cross-account access role ARN
# published by the aws-organization root's remote state. IAM Identity Center
# permission sets and assignments are delegated-administered from there (the
# instance itself is enabled out-of-band in the management account).
provider "aws" {
  region = var.aws_region
  assume_role {
    role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["shared_services"]
  }
}
