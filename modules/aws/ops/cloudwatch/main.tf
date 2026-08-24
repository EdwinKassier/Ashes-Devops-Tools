# CloudWatch metric alarms + optional SNS topic + optional dashboard — the AWS
# parity counterpart to GCP's monitoring/alert-policy and compute-dashboard.
# Dashboard/JSON bodies are built with jsonencode() (never
# data.aws_iam_policy_document) so they stay plan-known under mock_provider.

locals {
  sns_topic_arn = var.create_sns_topic ? aws_sns_topic.this[0].arn : var.sns_topic_arn
  alarm_actions = local.sns_topic_arn != null ? [local.sns_topic_arn] : []

  dashboard_body = jsonencode({
    widgets = length(var.dashboard_widgets) > 0 ? var.dashboard_widgets : [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# ${var.name_prefix} — no widgets configured. Populate var.dashboard_widgets."
        }
      }
    ]
  })
}

resource "aws_sns_topic" "this" {
  count             = var.create_sns_topic ? 1 : 0
  name              = "${var.name_prefix}-alarms"
  kms_master_key_id = var.sns_kms_master_key_id
  tags              = var.tags
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = var.alarms

  alarm_name          = "${var.name_prefix}-${each.key}"
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  dimensions          = each.value.dimensions
  treat_missing_data  = each.value.treat_missing_data
  unit                = each.value.unit
  alarm_description   = each.value.alarm_description

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_dashboard" "this" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = coalesce(var.dashboard_name, "${var.name_prefix}-dashboard")
  dashboard_body = local.dashboard_body
}
