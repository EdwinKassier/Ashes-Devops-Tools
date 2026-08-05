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

# Alarm on usage approaching the requested quota (~80%). Routes to the
# security-notifications SNS topic when one is supplied.
resource "aws_cloudwatch_metric_alarm" "usage" {
  for_each            = var.enable_service_quotas ? var.quota_increases : {}
  alarm_name          = "quota-usage-${each.key}"
  namespace           = "AWS/Usage"
  metric_name         = "ResourceCount"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = each.value.value * 0.8
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = var.notifications_topic_arn != "" ? [var.notifications_topic_arn] : []
}
