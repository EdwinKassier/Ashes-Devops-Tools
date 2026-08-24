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
  # checkov:skip=CKV2_AWS_10:No CloudWatch Logs group is attached by design. This org trail's authoritative, tamper-evident sink is the central Log-Archive S3 bucket (cross-account, with log-file validation digests). A CloudWatch Logs group would require a log group + IAM delivery role in the trail's account and duplicate the central S3-based delivery and downstream processing path; real-time analytics are handled by Security Lake / the SIEM reading from that bucket, not per-trail CloudWatch Logs.
  name                          = var.trail_name
  s3_bucket_name                = var.log_archive_bucket
  kms_key_id                    = var.kms_key_arn
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Audit finding A4 (opt-in): attach a CloudWatch Logs group so CIS control-plane
  # metric-filter alarms can fire in near-real-time. Default off preserves the
  # deliberate S3-only design (S3 is the authoritative sink; Security Lake/SIEM reads it).
  cloud_watch_logs_group_arn = var.enable_cloudwatch_logs ? "${aws_cloudwatch_log_group.trail[0].arn}:*" : null
  cloud_watch_logs_role_arn  = var.enable_cloudwatch_logs ? aws_iam_role.cloudtrail_cw[0].arn : null
}

# ---------------------------------------------------------------------------
# Audit finding A4 (opt-in, default OFF): near-real-time CIS control-plane alarms.
# PREVIEW (not yet validated against a real apply) against a real org — validate before enabling.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "trail" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/cloudtrail/${var.trail_name}"
  retention_in_days = var.cloudwatch_logs_retention_days
  # Audit C1: a CloudWatch Logs group can only use a CMK whose key policy grants
  # logs.<region>.amazonaws.com — the S3 trail CMK (var.kms_key_arn) does NOT, so
  # reusing it here fails CreateLogGroup. Use a SEPARATE, logs-granted key via
  # var.cloudwatch_logs_kms_key_arn; null = AWS-managed encryption (no grant needed).
  kms_key_id = var.cloudwatch_logs_kms_key_arn
}

resource "aws_iam_role" "cloudtrail_cw" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "${var.trail_name}-cloudwatch-delivery"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "cloudwatch-logs-delivery"
  role  = aws_iam_role.cloudtrail_cw[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail[0].arn}:*"
    }]
  })
}

# CIS control-plane metric filters + alarms (representative set).
locals {
  cis_metric_filters = var.enable_cloudwatch_logs ? {
    unauthorized-api-calls = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
    root-account-usage     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
    iam-policy-changes     = "{ ($.eventName = DeleteGroupPolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = DeleteUserPolicy) || ($.eventName = PutGroupPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = PutUserPolicy) || ($.eventName = CreatePolicy) || ($.eventName = DeletePolicy) || ($.eventName = AttachRolePolicy) || ($.eventName = DetachRolePolicy) }"
  } : {}
}

resource "aws_cloudwatch_log_metric_filter" "cis" {
  for_each       = local.cis_metric_filters
  name           = "${var.trail_name}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.trail[0].name
  pattern        = each.value
  metric_transformation {
    name      = "${var.trail_name}-${each.key}"
    namespace = "CISBenchmark"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "cis" {
  for_each            = local.cis_metric_filters
  alarm_name          = "${var.trail_name}-${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "${var.trail_name}-${each.key}"
  namespace           = "CISBenchmark"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "CIS control-plane alarm: ${each.key}"
  alarm_actions       = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"
}
