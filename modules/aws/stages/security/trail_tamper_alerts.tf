# Tamper alerts for the delegated-admin organization trail (security tooling;
# only with enable_cloudtrail_delegated_admin).
#
# The aws-organization org-guard-alerts rule sees only management-account API
# calls on the management trail. Calls on the delegated-admin trail are made
# from security tooling, so their "AWS API Call via CloudTrail" events reach
# security tooling's default bus. The SCP blocks them for every member
# principal except the exempt ones (the pipeline roles and
# OrganizationAccountAccessRole may still change selectors and update the
# trail; break-glass may also stop or delete it), so this rule makes every such
# call on the trail visible.
#
# One rule, in the trail's home Region (the security-tooling provider's, which
# created it): for a multi-Region trail these operations succeed only there
# (anywhere else they fail with InvalidHomeRegionException), so no cross-Region
# forwarding is needed. It publishes to the security-notifications topic in the
# same account and Region.

locals {
  # The trail is owned by the management account: name or ARN in any request.
  delegated_admin_trail_name    = var.aws.cloudtrail_delegated_admin_trail_name
  delegated_admin_trail_pattern = "arn:*:cloudtrail:*:${var.management_account_id}:trail/${local.delegated_admin_trail_name}"
  delegated_admin_trail_match   = [local.delegated_admin_trail_name, { wildcard = local.delegated_admin_trail_pattern }]

  delegated_admin_trail_alert_pattern = jsonencode({
    source        = ["aws.cloudtrail"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["cloudtrail.amazonaws.com"]
      "$or" = [
        {
          eventName         = ["StopLogging", "DeleteTrail", "UpdateTrail"]
          requestParameters = { name = local.delegated_admin_trail_match }
        },
        {
          eventName         = ["PutEventSelectors", "PutInsightSelectors"]
          requestParameters = { trailName = local.delegated_admin_trail_match }
        },
        {
          eventName         = ["RemoveTags"]
          requestParameters = { resourceId = [{ wildcard = local.delegated_admin_trail_pattern }] }
        },
        {
          eventName         = ["PutResourcePolicy", "DeleteResourcePolicy"]
          requestParameters = { resourceArn = [{ wildcard = local.delegated_admin_trail_pattern }] }
        },
      ]
    }
  })
}

resource "aws_cloudwatch_event_rule" "delegated_admin_trail_tamper" {
  count    = local.create_delegated_admin_trail ? 1 : 0
  provider = aws.security_tooling

  name          = "sec-notify-org-trail-tamper"
  description   = "Changes to the delegated-admin organization trail ${local.delegated_admin_trail_name} (stop, delete, update, selectors, tags, resource policy)."
  event_pattern = local.delegated_admin_trail_alert_pattern
}

resource "aws_cloudwatch_event_target" "delegated_admin_trail_tamper" {
  count    = local.create_delegated_admin_trail ? 1 : 0
  provider = aws.security_tooling

  rule      = aws_cloudwatch_event_rule.delegated_admin_trail_tamper[0].name
  target_id = "security-notifications"
  arn       = module.security_notifications.topic_arn
}
