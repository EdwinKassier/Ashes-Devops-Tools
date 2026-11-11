# Organization-wide CloudTrail for the SRA landing zone.
#
# Creates a single multi-Region organization trail that captures management and
# global-service events across every account in the organization and delivers
# them to the central Log-Archive bucket.
#
# This trail MUST be created via the management-account (or delegated-admin)
# provider: organization trails can only be created by the management or a
# CloudTrail delegated-administrator account. Either way the management account
# owns the trail (its ARN carries the management account ID); a delegated admin
# keeps the CloudWatch Logs group, its role, CMK, topic and alarms in its own
# account (set trail_owner_account_id). The s3_bucket_name is the
# Log-Archive bucket, which lives in a DIFFERENT account; delivery to it is
# authorized by that bucket's resource policy. The stage that composes this
# module wires a depends_on from the trail to the bucket policy so the policy
# exists before CloudTrail validates delivery — that ordering is a stage concern
# and is not expressed at this module level.
#
# enable_log_file_validation produces the digest files needed to prove log
# integrity, and is a non-negotiable control for an audit-grade org trail.
#
# Data events (CIS AWS 3.8 write / 3.9 read): S3 object-level events are
# recorded through advanced event selectors, WriteOnly by default. COST: data
# events are billed per event ($0.10 per 100,000 at list price) on an ORG trail
# that spans every account, so read events ("read"/"all") on busy buckets can
# dwarf the rest of the trail's cost. The log-archive bucket itself is excluded
# by default — CloudTrail's own PutObject deliveries would otherwise be recorded
# as data events about the log bucket, a self-amplifying loop.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  # --- Advanced event selectors -------------------------------------------
  s3_data_events_enabled = var.cloudtrail_s3_data_events != "none"

  s3_excluded_prefixes = distinct(concat(
    var.exclude_log_archive_bucket_from_data_events ? ["arn:${local.partition}:s3:::${var.log_archive_bucket}/"] : [],
    [for b in var.s3_data_events_excluded_bucket_arns : "${trimsuffix(b, "/")}/"],
  ))

  # readOnly: write -> "false", read -> "true", all -> no readOnly field.
  s3_read_only_filter = {
    write = ["false"]
    read  = ["true"]
    all   = []
    none  = []
  }[var.cloudtrail_s3_data_events]

  # Selectors are only emitted when at least one data-event class is on; with
  # none, the trail keeps its implicit "all management events" behaviour.
  use_advanced_selectors = local.s3_data_events_enabled || var.enable_lambda_data_events
}

resource "aws_cloudtrail" "org" {
  # checkov:skip=CKV_AWS_252:No SNS topic is attached by design. Delivery notifications for this org trail are handled centrally — the Log-Archive bucket lives in a dedicated account and drives downstream processing via S3 event/notification wiring owned by that account, not per-trail SNS. CIS alarms publish to their own KMS-encrypted topic (aws_sns_topic.cis_alarms).
  # checkov:skip=CKV2_AWS_10:CloudWatch Logs IS attached by default (enable_cloudwatch_logs = true) via count-indexed resources Checkov's graph cannot resolve. When an operator disables it, the authoritative tamper-evident sink remains the central Log-Archive S3 bucket (log-file validation digests) read by Security Lake / the SIEM.
  name                          = var.trail_name
  s3_bucket_name                = var.log_archive_bucket
  kms_key_id                    = var.kms_key_arn
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Near-real-time CIS control-plane alarms (CIS AWS section 4) read this group.
  cloud_watch_logs_group_arn = var.enable_cloudwatch_logs ? "${aws_cloudwatch_log_group.trail[0].arn}:*" : null
  cloud_watch_logs_role_arn  = var.enable_cloudwatch_logs ? local.cloudwatch_delivery_role_arn : null

  # When advanced selectors are used, management events must be selected
  # explicitly or the trail stops recording them.
  dynamic "advanced_event_selector" {
    for_each = local.use_advanced_selectors ? [1] : []
    content {
      name = "Management events"
      field_selector {
        field  = "eventCategory"
        equals = ["Management"]
      }
    }
  }

  dynamic "advanced_event_selector" {
    for_each = local.s3_data_events_enabled ? [1] : []
    content {
      name = "S3 object-level events (${var.cloudtrail_s3_data_events})"
      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }
      field_selector {
        field  = "resources.type"
        equals = ["AWS::S3::Object"]
      }
      dynamic "field_selector" {
        for_each = length(local.s3_read_only_filter) > 0 ? [1] : []
        content {
          field  = "readOnly"
          equals = local.s3_read_only_filter
        }
      }
      dynamic "field_selector" {
        for_each = length(local.s3_excluded_prefixes) > 0 ? [1] : []
        content {
          field           = "resources.ARN"
          not_starts_with = local.s3_excluded_prefixes
        }
      }
    }
  }

  dynamic "advanced_event_selector" {
    for_each = var.enable_lambda_data_events ? [1] : []
    content {
      name = "Lambda invoke events"
      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }
      field_selector {
        field  = "resources.type"
        equals = ["AWS::Lambda::Function"]
      }
    }
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Logs delivery + CIS AWS section-4 metric-filter alarms.
#
# Self-sufficient by default: when no cloudwatch_logs_kms_key_arn is supplied
# the module creates a dedicated CMK in the trail's (management) account whose
# key policy grants logs.<region>.amazonaws.com (scoped by the log-group
# encryption context) and cloudwatch.amazonaws.com (so alarms can publish to the
# KMS-encrypted SNS topic). The trail's S3 CMK is never reused here: it lives in
# the log-archive account and does not grant the logs service.
# ---------------------------------------------------------------------------

locals {
  create_cw_kms_key = var.enable_cloudwatch_logs && var.cloudwatch_logs_kms_key_arn == null
  cw_kms_key_arn    = local.create_cw_kms_key ? aws_kms_key.cloudwatch[0].arn : var.cloudwatch_logs_kms_key_arn

  cw_kms_key_admin_arn = coalesce(var.cloudwatch_logs_kms_key_admin_arn, "arn:${local.partition}:iam::${local.account_id}:root")

  cw_kms_key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "KeyAdministration"
        Effect    = "Allow"
        Principal = { AWS = local.cw_kms_key_admin_arn }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*"
          }
        }
      },
      {
        Sid       = "AllowCloudWatchAlarmsToEncryptedSns"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
      ],
      # The pipeline's day-2 access is by key policy, never by tag: refresh,
      # rotation, description, tags and aliases only. No PutKeyPolicy, grants,
      # disable or deletion; the root KeyAdministration statement above stays
      # the break-glass path.
      length(var.cloudwatch_logs_kms_key_manager_arns) == 0 ? [] : [
        {
          Sid       = "PipelineKeyManagement"
          Effect    = "Allow"
          Principal = { AWS = var.cloudwatch_logs_kms_key_manager_arns }
          Action = [
            "kms:Describe*", "kms:Get*", "kms:List*",
            "kms:EnableKeyRotation", "kms:UpdateKeyDescription",
            "kms:TagResource", "kms:UntagResource",
            "kms:CreateAlias", "kms:UpdateAlias", "kms:DeleteAlias",
          ]
          Resource = "*"
        },
      ],
      length(var.cloudwatch_logs_kms_key_manager_arns) == 0 ? [] : [
        {
          # The CMK encrypts the CIS alarm SNS topic and the trail log group;
          # creating or updating them needs data-key access through those
          # services only.
          Sid       = "PipelineKeyUseViaServices"
          Effect    = "Allow"
          Principal = { AWS = var.cloudwatch_logs_kms_key_manager_arns }
          Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
          Resource  = "*"
          Condition = {
            StringEquals = {
              "kms:ViaService" = ["sns.${local.region}.amazonaws.com", "logs.${local.region}.amazonaws.com"]
            }
          }
        },
    ])
  })
}

resource "aws_kms_key" "cloudwatch" {
  count                   = local.create_cw_kms_key ? 1 : 0
  description             = "CMK: CloudWatch Logs + CIS alarm SNS for org trail ${var.trail_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.cw_kms_key_policy
  tags                    = var.tags
}

resource "aws_kms_alias" "cloudwatch" {
  count         = local.create_cw_kms_key ? 1 : 0
  name          = "alias/${var.trail_name}-cloudwatch"
  target_key_id = aws_kms_key.cloudwatch[0].key_id
}

# ---------------------------------------------------------------------------
# Deletion guard
#
# prevent_destroy must be a static literal, so a terraform_data guard carries
# it. replace_triggered_by ties the guard to the key: a plan that destroys OR
# replaces the CloudWatch Logs key (which schedules the old key, and everything encrypted
# under it, for deletion) must also replace the guard, which prevent_destroy
# refuses. Setting enable_deletion_protection = false does not lift an existing
# guard (removing it is itself a destroy). To retire the key deliberately,
# first run:
#   terraform state rm '<module_address>.terraform_data.cloudwatch_kms_deletion_guard[0]'
# ---------------------------------------------------------------------------

resource "terraform_data" "cloudwatch_kms_deletion_guard" {
  count = local.create_cw_kms_key && var.enable_deletion_protection ? 1 : 0

  input = "alias/${var.trail_name}-cloudwatch"

  lifecycle {
    prevent_destroy      = true
    replace_triggered_by = [aws_kms_key.cloudwatch[0].id]
  }
}

resource "aws_cloudwatch_log_group" "trail" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/cloudtrail/${var.trail_name}"
  retention_in_days = var.cloudwatch_logs_retention_days
  kms_key_id        = local.cw_kms_key_arn
  tags              = var.tags
}

# The delivery role is created here only when no existing one is passed in.
# The landing zone passes the role aws-organization creates, so the
# least-privilege aws-security role needs no IAM write at all: in the
# management account (outside every SCP) any role write is an escalation path.
#
# A trail created by a CloudTrail delegated administrator is owned by the
# management account (trail_owner_account_id), while its log group and this
# role live in the calling account. AWS documents aws:SourceAccount as the
# trail owner (the management account for organization trails), so the trust
# accepts the owner as well as this account.
locals {
  create_cloudwatch_delivery_role = var.enable_cloudwatch_logs && var.cloudwatch_logs_role_arn == null
  cloudwatch_delivery_role_arn    = local.create_cloudwatch_delivery_role ? try(aws_iam_role.cloudtrail_cw[0].arn, null) : var.cloudwatch_logs_role_arn

  delivery_source_accounts = distinct(compact([local.account_id, var.trail_owner_account_id]))
  # A single account stays a string, so an existing role's trust is unchanged
  # (round-tripped through JSON: the two branches have different types).
  delivery_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = jsondecode(length(local.delivery_source_accounts) == 1 ? jsonencode(local.delivery_source_accounts[0]) : jsonencode(local.delivery_source_accounts))
        }
      }
    }]
  })
}

resource "aws_iam_role" "cloudtrail_cw" {
  count                = local.create_cloudwatch_delivery_role ? 1 : 0
  name                 = "${var.trail_name}-cloudwatch-delivery"
  permissions_boundary = var.cloudwatch_logs_role_permissions_boundary_arn
  assume_role_policy   = local.delivery_trust
  tags                 = var.tags
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  count = local.create_cloudwatch_delivery_role ? 1 : 0
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

# --- Alarm notification topic (KMS-encrypted) ------------------------------

locals {
  create_alarm_topic = var.enable_cloudwatch_logs && var.alarm_sns_topic_arn == null
  alarm_topic_arn    = local.create_alarm_topic ? aws_sns_topic.cis_alarms[0].arn : var.alarm_sns_topic_arn
}

resource "aws_sns_topic" "cis_alarms" {
  count             = local.create_alarm_topic ? 1 : 0
  name              = "${var.trail_name}-cis-alarms"
  kms_master_key_id = local.cw_kms_key_arn
  tags              = var.tags
}

resource "aws_sns_topic_policy" "cis_alarms" {
  count = local.create_alarm_topic ? 1 : 0
  arn   = aws_sns_topic.cis_alarms[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudWatchAlarmsPublish"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.cis_alarms[0].arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "cis_alarms" {
  for_each  = local.create_alarm_topic ? var.alarm_subscriptions : {}
  topic_arn = aws_sns_topic.cis_alarms[0].arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint
}

# --- CIS AWS Foundations section-4 metric filters --------------------------
#
# Catalogue of the CIS AWS Foundations Benchmark (v3.0 / v5.0) section-4
# monitoring controls that are implemented as CloudTrail metric filters
# (Security Hub CloudWatch.1-14 equivalents). Patterns follow the benchmark's
# remediation text; the unauthorized-API pattern carries the v3 noise filters
# with explicit parentheses (CloudWatch evaluates && before || otherwise).

locals {
  cis_metric_filter_catalog = {
    unauthorized-api-calls = {
      cis_id  = "4.1"
      pattern = "{ (($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\")) && ($.sourceIPAddress != \"delivery.logs.amazonaws.com\") && ($.eventName != \"HeadBucket\") }"
    }
    console-signin-without-mfa = {
      cis_id  = "4.2"
      pattern = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
    }
    root-account-usage = {
      cis_id  = "4.3"
      pattern = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
    }
    iam-policy-changes = {
      cis_id  = "4.4"
      pattern = "{ ($.eventSource = iam.amazonaws.com) && (($.eventName = DeleteGroupPolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = DeleteUserPolicy) || ($.eventName = PutGroupPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = PutUserPolicy) || ($.eventName = CreatePolicy) || ($.eventName = DeletePolicy) || ($.eventName = CreatePolicyVersion) || ($.eventName = DeletePolicyVersion) || ($.eventName = AttachRolePolicy) || ($.eventName = DetachRolePolicy) || ($.eventName = AttachUserPolicy) || ($.eventName = DetachUserPolicy) || ($.eventName = AttachGroupPolicy) || ($.eventName = DetachGroupPolicy)) }"
    }
    cloudtrail-config-changes = {
      cis_id  = "4.5"
      pattern = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }"
    }
    console-auth-failures = {
      cis_id  = "4.6"
      pattern = "{ ($.eventName = ConsoleLogin) && ($.errorMessage = \"Failed authentication\") }"
    }
    cmk-disable-or-deletion = {
      cis_id  = "4.7"
      pattern = "{ ($.eventSource = kms.amazonaws.com) && (($.eventName = DisableKey) || ($.eventName = ScheduleKeyDeletion)) }"
    }
    s3-bucket-policy-changes = {
      cis_id  = "4.8"
      pattern = "{ ($.eventSource = s3.amazonaws.com) && (($.eventName = PutBucketAcl) || ($.eventName = PutBucketPolicy) || ($.eventName = PutBucketCors) || ($.eventName = PutBucketLifecycle) || ($.eventName = PutBucketReplication) || ($.eventName = DeleteBucketPolicy) || ($.eventName = DeleteBucketCors) || ($.eventName = DeleteBucketLifecycle) || ($.eventName = DeleteBucketReplication)) }"
    }
    config-changes = {
      cis_id  = "4.9"
      pattern = "{ ($.eventSource = config.amazonaws.com) && (($.eventName = StopConfigurationRecorder) || ($.eventName = DeleteDeliveryChannel) || ($.eventName = PutDeliveryChannel) || ($.eventName = PutConfigurationRecorder)) }"
    }
    security-group-changes = {
      cis_id  = "4.10"
      pattern = "{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }"
    }
    nacl-changes = {
      cis_id  = "4.11"
      pattern = "{ ($.eventName = CreateNetworkAcl) || ($.eventName = CreateNetworkAclEntry) || ($.eventName = DeleteNetworkAcl) || ($.eventName = DeleteNetworkAclEntry) || ($.eventName = ReplaceNetworkAclEntry) || ($.eventName = ReplaceNetworkAclAssociation) }"
    }
    network-gateway-changes = {
      cis_id  = "4.12"
      pattern = "{ ($.eventName = CreateCustomerGateway) || ($.eventName = DeleteCustomerGateway) || ($.eventName = AttachInternetGateway) || ($.eventName = CreateInternetGateway) || ($.eventName = DeleteInternetGateway) || ($.eventName = DetachInternetGateway) }"
    }
    route-table-changes = {
      cis_id  = "4.13"
      pattern = "{ ($.eventSource = ec2.amazonaws.com) && (($.eventName = CreateRoute) || ($.eventName = CreateRouteTable) || ($.eventName = ReplaceRoute) || ($.eventName = ReplaceRouteTableAssociation) || ($.eventName = DeleteRouteTable) || ($.eventName = DeleteRoute) || ($.eventName = DisassociateRouteTable)) }"
    }
    vpc-changes = {
      cis_id  = "4.14"
      pattern = "{ ($.eventName = CreateVpc) || ($.eventName = DeleteVpc) || ($.eventName = ModifyVpcAttribute) || ($.eventName = AcceptVpcPeeringConnection) || ($.eventName = CreateVpcPeeringConnection) || ($.eventName = DeleteVpcPeeringConnection) || ($.eventName = RejectVpcPeeringConnection) || ($.eventName = AttachClassicLinkVpc) || ($.eventName = DetachClassicLinkVpc) || ($.eventName = DisableVpcClassicLink) || ($.eventName = EnableVpcClassicLink) }"
    }
    organizations-changes = {
      cis_id  = "4.15"
      pattern = "{ ($.eventSource = organizations.amazonaws.com) && (($.eventName = AcceptHandshake) || ($.eventName = AttachPolicy) || ($.eventName = CreateAccount) || ($.eventName = CreateOrganizationalUnit) || ($.eventName = CreatePolicy) || ($.eventName = DeclineHandshake) || ($.eventName = DeleteOrganization) || ($.eventName = DeleteOrganizationalUnit) || ($.eventName = DeletePolicy) || ($.eventName = DetachPolicy) || ($.eventName = DisablePolicyType) || ($.eventName = EnablePolicyType) || ($.eventName = InviteAccountToOrganization) || ($.eventName = LeaveOrganization) || ($.eventName = MoveAccount) || ($.eventName = RemoveAccountFromOrganization) || ($.eventName = UpdatePolicy) || ($.eventName = UpdateOrganizationalUnit)) }"
    }
  }

  cis_metric_filters = var.enable_cloudwatch_logs ? {
    for k, v in local.cis_metric_filter_catalog : k => v if !contains(var.cis_alarms_excluded, k)
  } : {}
}

resource "aws_cloudwatch_log_metric_filter" "cis" {
  for_each       = local.cis_metric_filters
  name           = "${var.trail_name}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.trail[0].name
  pattern        = each.value.pattern
  metric_transformation {
    name      = "${var.trail_name}-${each.key}"
    namespace = var.cis_metric_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "cis" {
  for_each            = local.cis_metric_filters
  alarm_name          = "${var.trail_name}-${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.cis[each.key].metric_transformation[0].name
  namespace           = var.cis_metric_namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "CIS AWS Foundations ${each.value.cis_id}: ${each.key} (org trail ${var.trail_name})"
  alarm_actions       = local.alarm_topic_arn != null ? [local.alarm_topic_arn] : []
  treat_missing_data  = "notBreaching"
  tags                = var.tags
}
