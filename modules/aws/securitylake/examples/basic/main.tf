# Basic working example for the aws/securitylake module.
#
# Runs entirely in the delegated-administrator (Security Tooling) account, so a
# single default provider is sufficient. Run `terraform init && terraform
# validate` here to check it.

provider "aws" {
  region = "eu-west-2"
}

module "securitylake" {
  source = "../../"

  meta_store_manager_role_arn = "arn:aws:iam::111111111111:role/AmazonSecurityLakeMetaStoreManager"
  kms_key_id                  = "arn:aws:kms:eu-west-2:111111111111:key/abcd1234-ab12-cd34-ef56-abcdef123456"

  providers = {
    aws = aws
  }
}
