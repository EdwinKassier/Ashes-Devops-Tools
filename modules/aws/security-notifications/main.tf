# Security-notifications detective control for the SRA landing zone.
#
# Provisions a KMS-encrypted SNS topic and a set of EventBridge rules that fan
# the key detective signals (GuardDuty / Security Hub findings, root-account
# usage, console sign-in without MFA, org-access-role and break-glass-role use)
# into that topic, plus a Security Hub automation rule that auto-notes
# informational findings. The whole module is gated behind
# enable_security_notifications.
#
# These are DETECTIVE controls: they observe and alert, they do not block. The
# preventive counterparts live elsewhere (the B3 SCP carve-out and the F1
# disabled-by-default guardrail). The break-glass detective control lives HERE
# rather than in the iam-role module, which only defines the role itself; the
# alarm depends on the org CloudTrail (C3) delivering STS events into the
# observed account.

# KMS-encrypted SNS topic that all security notifications are published to.
resource "aws_sns_topic" "this" {
  count             = var.enable_security_notifications ? 1 : 0
  name              = var.topic_name
  kms_master_key_id = var.kms_key_id
}

# Allow EventBridge and CloudWatch to publish into the topic.
resource "aws_sns_topic_policy" "this" {
  count = var.enable_security_notifications ? 1 : 0
  arn   = aws_sns_topic.this[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeAndCloudWatchPublish"
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "cloudwatch.amazonaws.com"] }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.this[0].arn
    }]
  })
}

# Subscribers (email / https / …). A subscriber is REQUIRED when the module is
# enabled (enforced by the variable validation) — otherwise findings fire into
# a void.
resource "aws_sns_topic_subscription" "this" {
  for_each  = var.enable_security_notifications ? var.notification_subscribers : {}
  topic_arn = aws_sns_topic.this[0].arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint
}

# EventBridge rules -> SNS for the key detective signals. Each rule carries a
# distinct event-pattern shape, so the map is built unconditionally and each
# pattern is pre-encoded to JSON to keep the value type uniform; the enable
# flag gates it to an empty map.
locals {
  all_event_rules = {
    guardduty-findings   = jsonencode({ source = ["aws.guardduty"], detail-type = ["GuardDuty Finding"] })
    securityhub-findings = jsonencode({ source = ["aws.securityhub"], detail-type = ["Security Hub Findings - Imported"] })
    root-account-usage   = jsonencode({ source = ["aws.signin", "aws.sts"], detail = { userIdentity = { type = ["Root"] } } })
    org-access-role-use  = jsonencode({ source = ["aws.sts"], detail = { requestParameters = { roleSessionName = [{ prefix = "OrganizationAccountAccessRole" }] } } })
    console-no-mfa       = jsonencode({ source = ["aws.signin"], detail-type = ["AWS Console Sign In via CloudTrail"], detail = { additionalEventData = { MFAUsed = ["No"] } } })
    break-glass-use      = jsonencode({ source = ["aws.sts"], detail = { requestParameters = { roleArn = [var.break_glass_role_arn] } } })
  }
  event_rules = var.enable_security_notifications ? local.all_event_rules : {}
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each      = local.event_rules
  name          = "sec-notify-${each.key}"
  event_pattern = each.value
}

resource "aws_cloudwatch_event_target" "this" {
  for_each  = local.event_rules
  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = each.key
  arn       = aws_sns_topic.this[0].arn
}

# Security Hub automation rule: auto-note informational findings so operators
# are not paged for background noise while keeping an audit trail.
resource "aws_securityhub_automation_rule" "suppress_known" {
  count       = var.enable_security_notifications ? 1 : 0
  rule_name   = var.automation_rule_name
  description = "Auto-note informational known findings"
  rule_order  = 1

  criteria {
    severity_label {
      comparison = "EQUALS"
      value      = "INFORMATIONAL"
    }
  }

  actions {
    type = "FINDING_FIELDS_UPDATE"
    finding_fields_update {
      note {
        text       = "auto-noted by security-notifications"
        updated_by = "terraform"
      }
    }
  }
}
