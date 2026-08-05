# Resource-assertion tests for the aws/log-archive-bucket module.
#
# The bucket policy is built with jsonencode() in locals, so its JSON is real
# under mock_provider and the can(regex(...)) assertion below is meaningful.

mock_provider "aws" {}

variables {
  log_archive_bucket_name = "acme-org-log-archive"
  kms_key_arn             = "arn:aws:kms:eu-west-1:111122223333:key/abcd-1234"
  org_id                  = "o-abc123xyz0"
}

run "bucket_hardening_configured" {
  command = plan

  # All four Block Public Access dimensions must be enabled.
  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls == true &&
      aws_s3_bucket_public_access_block.this.block_public_policy == true &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls == true &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets == true
    )
    error_message = "All four Block Public Access booleans must be true"
  }

  assert {
    condition     = aws_s3_bucket.this.object_lock_enabled == true
    error_message = "Object Lock must be enabled at bucket creation"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be Enabled"
  }

  assert {
    condition     = aws_s3_bucket_object_lock_configuration.this.rule[0].default_retention[0].mode == "COMPLIANCE"
    error_message = "Default Object Lock mode must be COMPLIANCE"
  }

  # aws:SourceOrgID scoping present in the bucket policy JSON.
  assert {
    condition     = can(regex("aws:SourceOrgID", aws_s3_bucket_policy.this.policy))
    error_message = "Bucket policy must scope log-delivery grants by aws:SourceOrgID"
  }

  # Non-TLS access is denied.
  assert {
    condition     = can(regex("aws:SecureTransport", aws_s3_bucket_policy.this.policy))
    error_message = "Bucket policy must deny non-TLS (aws:SecureTransport) access"
  }
}
