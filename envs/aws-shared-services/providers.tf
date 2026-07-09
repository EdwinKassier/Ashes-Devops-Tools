# Phase-2 shared-services root. A SINGLE default provider that authenticates into
# the SHARED SERVICES account by assuming the cross-account access role ARN
# published by the aws-organization root's remote state. All shared-services
# resources (ACM Private CA, Secrets Manager baseline) live in that one account.
provider "aws" {
  region = var.aws_region
  assume_role {
    role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["shared_services"]
  }
}
