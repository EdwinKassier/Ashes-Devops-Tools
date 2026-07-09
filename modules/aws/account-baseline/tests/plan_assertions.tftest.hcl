# Resource-assertion tests for the aws/account-baseline module.
#
# Asserts on configured attributes known at plan time under mock_provider:
# the per-Region EBS encryption flag and the four S3 Block Public Access
# booleans.

mock_provider "aws" {}

run "defaults_enforce_encryption_and_bpa" {
  command = plan

  assert {
    condition     = aws_ebs_encryption_by_default.this["eu-west-2"].enabled == true
    error_message = "Default EBS encryption must be enabled in the home Region."
  }

  assert {
    condition = (
      aws_s3_account_public_access_block.this.block_public_acls == true &&
      aws_s3_account_public_access_block.this.block_public_policy == true &&
      aws_s3_account_public_access_block.this.ignore_public_acls == true &&
      aws_s3_account_public_access_block.this.restrict_public_buckets == true
    )
    error_message = "All four account-level S3 Block Public Access settings must be true."
  }
}
