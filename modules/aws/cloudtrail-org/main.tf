# Organization-wide CloudTrail for the SRA landing zone.
#
# Creates a single multi-Region organization trail that captures management and
# global-service events across every account in the organization and delivers
# them to the central Log-Archive bucket.
#
# This trail MUST be created via the management-account (or delegated-admin)
# provider: organization trails can only be owned by the management or a
# CloudTrail delegated-administrator account. The s3_bucket_name is the
# Log-Archive bucket, which lives in a DIFFERENT account; delivery to it is
# authorized by that bucket's resource policy. The stage that composes this
# module wires a depends_on from the trail to the bucket policy so the policy
# exists before CloudTrail validates delivery — that ordering is a stage concern
# and is not expressed at this module level.
#
# enable_log_file_validation produces the digest files needed to prove log
# integrity, and is a non-negotiable control for an audit-grade org trail.

resource "aws_cloudtrail" "org" {
  # checkov:skip=CKV_AWS_252:No SNS topic is attached by design. Delivery notifications for this org trail are handled centrally — the Log-Archive bucket lives in a dedicated account and drives downstream processing via S3 event/notification wiring owned by that account, not per-trail SNS. Adding an SNS topic here would require a topic in the trail's account and duplicate that central path.
  name                          = var.trail_name
  s3_bucket_name                = var.log_archive_bucket
  kms_key_id                    = var.kms_key_arn
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
}
