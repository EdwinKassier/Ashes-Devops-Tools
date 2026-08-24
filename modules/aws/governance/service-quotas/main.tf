# Service-quota management for the SRA landing zone.
#
# Opt-in (disabled by default). For each requested quota increase it files a
# service-quota request and provisions an AWS/Usage CloudWatch alarm that fires
# at ~80% of the requested value, routing to the security-notifications SNS
# topic. This implements Well-Architected REL01-BP04/05 (monitor and manage
# service quotas).

# File the quota-increase request for each entry.
resource "aws_servicequotas_service_quota" "this" {
  for_each     = var.enable_service_quotas ? var.quota_increases : {}
  quota_code   = each.value.quota_code
  service_code = each.value.service_code
  value        = each.value.value
}

locals {
  # AWS/Usage ResourceCount REQUIRES Service/Class/Type/Resource dimensions
  #. Without them the alarm binds to no metric and is stuck in
  # INSUFFICIENT_DATA forever. Only build alarms for entries that supply the
  # usage_metric dimensions — an entry without them files the quota request but
  # gets no (inert) alarm.
  quota_alarms = {
    for k, q in var.quota_increases : k => q if q.usage_metric != null
  }
}

# Alarm on usage approaching the requested quota (~80%). Routes to the
# security-notifications SNS topic when one is supplied.
resource "aws_cloudwatch_metric_alarm" "usage" {
  for_each            = var.enable_service_quotas ? local.quota_alarms : {}
  alarm_name          = "quota-usage-${each.key}"
  namespace           = "AWS/Usage"
  metric_name         = "ResourceCount"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = each.value.value * 0.8
  comparison_operator = "GreaterThanOrEqualToThreshold"
  # Missing usage data (no resources yet) is not a breach — avoids false ALARM.
  treat_missing_data = "notBreaching"

  # Required dimensions for the AWS/Usage namespace.
  dimensions = {
    Service  = each.value.usage_metric.service
    Class    = each.value.usage_metric.class
    Type     = each.value.usage_metric.type
    Resource = each.value.usage_metric.resource
  }

  alarm_actions = var.notifications_topic_arn != "" ? [var.notifications_topic_arn] : []
}
