# Org-detection guard alerts (management account, owned by aws-organization).
#
# The aws-security management role registers the security services' delegated
# admins and wires the organization trail. Turning org-wide detection OFF
# (Disable*AdminAccount, DisableAWSServiceAccess, DeregisterDelegatedAdministrator)
# is gated off on that role, and trail selector changes are allowed but must
# be SEEN. These alerts live here, outside the aws-security role's reach (it has
# no events:* and its sns:* is scoped to <trail>-* topics), so the pipeline
# being watched cannot silence them.
#
# Organizations events reach EventBridge only in us-east-1; GuardDuty, Security
# Hub, Macie, Inspector and CloudTrail calls are regional. A rule can only
# target SNS in its own region, so every other enabled region forwards matching
# events to the us-east-1 default bus, where one rule publishes to the topic.

locals {
  guard_home_region = "us-east-1"
  guard_name        = "org-guard-alerts"
  guard_account_id  = module.organization.management_account_id

  guard_home_bus_arn = "arn:${var.partition}:events:${local.guard_home_region}:${local.guard_account_id}:event-bus/default"
  guard_rule_arn     = "arn:${var.partition}:events:${local.guard_home_region}:${local.guard_account_id}:rule/${local.guard_name}"
  guard_trail_arn    = "arn:${var.partition}:cloudtrail:*:${local.guard_account_id}:trail/${var.org_trail_name}"

  guard_trail_log_group = "/aws/cloudtrail/${var.org_trail_name}"
  guard_cis_topic       = "${var.org_trail_name}-cis-alarms"

  # Every enabled region plus the org trail's home region (its log group, CIS
  # alarms and topic live there), minus us-east-1, which has the main rule.
  guard_forward_regions = setsubtract(setunion(toset(var.aws_enabled_regions), [var.org_trail_home_region]), [local.guard_home_region])

  # "AWS API Call via CloudTrail" events. EventBridge receives these only for
  # management events that CloudTrail records, so the alerts depend on the
  # org trail logging management (write) events: a selector change that drops
  # them is itself the first thing matched below.
  guard_event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      "$or" = concat([
        {
          eventSource = ["organizations.amazonaws.com"]
          eventName   = ["DisableAWSServiceAccess", "DeregisterDelegatedAdministrator"]
        },
        {
          # Not matched by the CIS 4.5 CloudTrail-configuration alarm.
          eventSource = ["cloudtrail.amazonaws.com"]
          eventName   = ["PutEventSelectors", "PutInsightSelectors"]
          requestParameters = {
            trailName = [var.org_trail_name, { wildcard = local.guard_trail_arn }]
          }
        },
        {
          eventSource = ["cloudtrail.amazonaws.com"]
          eventName   = ["RemoveTags"]
          requestParameters = {
            resourceId = [{ wildcard = local.guard_trail_arn }]
          }
        },
        {
          eventSource = ["guardduty.amazonaws.com", "securityhub.amazonaws.com", "macie2.amazonaws.com", "detective.amazonaws.com"]
          eventName   = ["DisableOrganizationAdminAccount"]
        },
        {
          eventSource = ["inspector2.amazonaws.com"]
          eventName   = ["DisableDelegatedAdminAccount"]
        },
        {
          eventSource = ["fms.amazonaws.com"]
          eventName   = ["DisassociateAdminAccount"]
        },
        # Detect-only: the aws-security role may still PutMetricAlarm on the
        # CIS alarms. Silencing one (actions disabled, or no alarm actions) is
        # matched here; deleting or disabling one is also denied on the role.
        {
          eventSource = ["monitoring.amazonaws.com"]
          eventName   = ["PutMetricAlarm"]
          requestParameters = {
            alarmName      = [{ wildcard = "${var.org_trail_name}-*" }]
            actionsEnabled = [false]
          }
        },
        {
          eventSource = ["monitoring.amazonaws.com"]
          eventName   = ["PutMetricAlarm"]
          requestParameters = {
            alarmName    = [{ wildcard = "${var.org_trail_name}-*" }]
            alarmActions = [{ exists = false }]
          }
        },
        {
          eventSource       = ["monitoring.amazonaws.com"]
          eventName         = ["DeleteAlarms", "DisableAlarmActions"]
          requestParameters = { alarmNames = [{ wildcard = "${var.org_trail_name}-*" }] }
        },
        # The CIS alarm topic (the role holds sns:* on <trail>-* topics).
        {
          eventSource       = ["sns.amazonaws.com"]
          eventName         = ["DeleteTopic", "SetTopicAttributes"]
          requestParameters = { topicArn = [{ wildcard = "*:${local.guard_cis_topic}" }] }
        },
        {
          eventSource       = ["sns.amazonaws.com"]
          eventName         = ["Unsubscribe"]
          requestParameters = { subscriptionArn = [{ wildcard = "*:${local.guard_cis_topic}:*" }] }
        },
        # Overwriting a CIS metric filter, or deleting trail log streams.
        {
          eventSource       = ["logs.amazonaws.com"]
          eventName         = ["PutMetricFilter", "DeleteMetricFilter", "DeleteLogStream"]
          requestParameters = { logGroupName = [local.guard_trail_log_group] }
        },
        ],
        # With the CloudTrail delegated admin, the organization trail is managed
        # from security tooling (alerted there by aws-security) and nothing in
        # the management account has a trail write left except the phase-0 and
        # break-glass roles, which SCPs never constrain. Any trail change made
        # here, on any trail name, is then an alert.
        [for c in [{
          eventSource = ["cloudtrail.amazonaws.com"]
          eventName   = ["StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors", "PutInsightSelectors", "RemoveTags", "PutResourcePolicy", "DeleteResourcePolicy"]
        }] : c if var.enable_cloudtrail_delegated_admin],
      )
    }
  })
}

resource "aws_kms_key" "guard_alerts" {
  region = local.guard_home_region

  description             = "Encrypts the ${local.guard_name} SNS topic (org-detection guard alerts)."
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # KMS rejects a policy that would lock the account out.
        Sid       = "AccountRoot"
        Effect    = "Allow"
        Principal = { AWS = "arn:${var.partition}:iam::${local.guard_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # EventBridge publishes to the encrypted topic.
        Sid       = "EventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "guard_alerts" {
  region = local.guard_home_region

  name          = "alias/${local.guard_name}"
  target_key_id = aws_kms_key.guard_alerts.key_id
}

resource "aws_sns_topic" "guard_alerts" {
  region = local.guard_home_region

  name              = local.guard_name
  kms_master_key_id = aws_kms_key.guard_alerts.arn

  lifecycle {
    # The aws-security role holds sns:* on <trail>-* topics: the guard topic
    # must never fall under that prefix.
    precondition {
      condition     = !startswith(local.guard_name, "${var.org_trail_name}-")
      error_message = "org_trail_name must not be a prefix of org-guard-alerts: the aws-security role could then manage the guard topic."
    }
  }
}

resource "aws_sns_topic_policy" "guard_alerts" {
  region = local.guard_home_region

  arn = aws_sns_topic.guard_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "GuardRulePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.guard_alerts.arn
        Condition = { ArnEquals = { "aws:SourceArn" = local.guard_rule_arn } }
      },
      {
        Sid       = "AccountManage"
        Effect    = "Allow"
        Principal = { AWS = "arn:${var.partition}:iam::${local.guard_account_id}:root" }
        Action = [
          "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:AddPermission", "sns:RemovePermission",
          "sns:DeleteTopic", "sns:Subscribe", "sns:ListSubscriptionsByTopic", "sns:Publish",
        ]
        Resource = aws_sns_topic.guard_alerts.arn
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "guard_alerts" {
  for_each = toset(var.guard_alert_emails)

  region = local.guard_home_region

  topic_arn = aws_sns_topic.guard_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_event_rule" "guard_alerts" {
  region = local.guard_home_region

  name          = local.guard_name
  description   = "Org-detection teardown and organization-trail tampering calls (management account)."
  event_pattern = local.guard_event_pattern
}

resource "aws_cloudwatch_event_target" "guard_alerts" {
  region = local.guard_home_region

  rule      = aws_cloudwatch_event_rule.guard_alerts.name
  target_id = "sns"
  arn       = aws_sns_topic.guard_alerts.arn
}

# EventBridge -> us-east-1 default bus. Every event-bus target needs role_arn.
resource "aws_iam_role" "guard_alerts_forwarder" {
  name = "${local.guard_name}-forwarder"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.guard_account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "guard_alerts_forwarder" {
  name = "put-events-us-east-1-default-bus"
  role = aws_iam_role.guard_alerts_forwarder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = local.guard_home_bus_arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "guard_alerts_forward" {
  for_each = local.guard_forward_regions

  region = each.value

  name          = "${local.guard_name}-forward"
  description   = "Forwards org-detection teardown and trail-tampering calls to the ${local.guard_home_region} default bus."
  event_pattern = local.guard_event_pattern
}

resource "aws_cloudwatch_event_target" "guard_alerts_forward" {
  for_each = local.guard_forward_regions

  region = each.value

  rule      = aws_cloudwatch_event_rule.guard_alerts_forward[each.key].name
  target_id = "us-east-1-default-bus"
  arn       = local.guard_home_bus_arn
  role_arn  = aws_iam_role.guard_alerts_forwarder.arn
}

# Without subscribers the topic still records alerts, but nobody is told.
check "guard_alert_emails_set" {
  assert {
    condition     = length(var.guard_alert_emails) > 0
    error_message = "No guard_alert_emails (aws.guard_alert_emails) are set: org-guard-alerts fires when org-wide detection is disabled or the org trail / CIS alarms are tampered with, but nobody is emailed. Set at least one address (or subscribe the topic another way)."
  }
}
