# Phase-2 network root. A SINGLE default provider that authenticates into the
# NETWORK account by assuming the cross-account access role ARN published by the
# aws-organization root's remote state. All network-hub resources (TGW, IPAM,
# inspection/egress VPCs, Route 53 resolver, endpoints) live in that one account.
provider "aws" {
  region = var.aws_region
  assume_role {
    role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["network"]
  }
}
