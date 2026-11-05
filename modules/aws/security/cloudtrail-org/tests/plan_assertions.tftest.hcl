# Resource-assertion tests for the aws/cloudtrail-org module.
#
# Asserts on configured attributes of the trail, which are known at plan time
# under mock_provider. Provider-computed attributes (arn) are deliberately not
# asserted on here.

mock_provider "aws" {}

run "org_trail_is_multi_region_with_log_validation" {
  command = plan

  variables {
    log_archive_bucket = "sra-log-archive-bucket"
    kms_key_arn        = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_cloudtrail.org.is_organization_trail == true && aws_cloudtrail.org.is_multi_region_trail == true && aws_cloudtrail.org.enable_log_file_validation == true
    error_message = "Org trail must be an organization trail, multi-Region, and have log-file validation enabled"
  }

  assert {
    condition     = aws_cloudtrail.org.include_global_service_events == true
    error_message = "Org trail must include global service events"
  }

  # Structural (M6): the trail is CMEK-encrypted with the supplied key and
  # delivers to the log-archive bucket.
  assert {
    condition     = aws_cloudtrail.org.kms_key_id == var.kms_key_arn && aws_cloudtrail.org.s3_bucket_name == var.log_archive_bucket
    error_message = "Org trail must be CMEK-encrypted with the provided key and deliver to the log-archive bucket"
  }

  # Structural (M6): management events only — no data-event selectors (the
  # cost-conscious default; data events would add per-event charges).
  assert {
    condition     = length(aws_cloudtrail.org.event_selector) == 0 && length(aws_cloudtrail.org.advanced_event_selector) == 0
    error_message = "Org trail must record management events only (no data-event selectors)"
  }
}
