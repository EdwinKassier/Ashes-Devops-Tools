# Resource-assertion tests for the aws/systems-manager module.
#
# Asserts on configured attributes that are known at plan time under
# mock_provider: the rendered Session Manager document content and the default
# patch baseline operating system.

mock_provider "aws" {}

variables {
  log_bucket_name = "org-ssm-session-logs"
  kms_key_id      = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
}

run "session_document_carries_logging_and_kms" {
  command = plan

  assert {
    condition     = can(regex("org-ssm-session-logs", aws_ssm_document.session_preferences.content))
    error_message = "Session document content must reference the S3 log bucket name"
  }

  assert {
    condition     = can(regex("cloudWatchLogGroupName", aws_ssm_document.session_preferences.content))
    error_message = "Session document content must configure a CloudWatch log group"
  }

  assert {
    condition     = can(regex("kmsKeyId", aws_ssm_document.session_preferences.content))
    error_message = "Session document content must configure a KMS key"
  }

  assert {
    condition     = aws_ssm_default_patch_baseline.this.operating_system == "AMAZON_LINUX_2"
    error_message = "Default patch baseline must target AMAZON_LINUX_2"
  }

  assert {
    condition     = aws_ssm_association.inventory.name == "AWS-GatherSoftwareInventory"
    error_message = "Inventory association must use the AWS-managed GatherSoftwareInventory document"
  }
}
