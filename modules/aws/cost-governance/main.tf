# Management-account-scoped cost governance for the SRA landing zone.
#
# Budgets, Cost Anomaly Detection and cost-allocation-tag activation are all
# management-account (payer) concerns: consolidated billing rolls every member
# account's spend up to the payer, so the budget/anomaly view is organization-
# wide only from here. This module is therefore composed by the aws-organization
# stage, whose default provider IS the management account.
#
#   - aws_budgets_budget          — per-key monthly COST budgets with a percentage
#                                    threshold notification (SNS + email fan-out).
#   - aws_ce_anomaly_monitor      — a DIMENSIONAL/SERVICE monitor that watches the
#                                    always-on services (Convention 10), so spend
#                                    spikes on any service surface as anomalies.
#   - aws_ce_anomaly_subscription — DAILY email alerting above an absolute-impact
#                                    threshold, wired to the monitor above.
#   - aws_ce_cost_allocation_tag  — activates the B3 tag-policy keys in Cost
#                                    Explorer / the Cost & Usage Report so spend
#                                    can be sliced by CostCenter / Environment /
#                                    Owner.
#
# Everything is gated behind enable_cost_governance so a non-management root (or
# a plan that must stay credential-free) can compose the module as a no-op.

resource "aws_budgets_budget" "this" {
  for_each = var.enable_cost_governance ? var.budgets : {}

  name         = each.key
  budget_type  = "COST"
  limit_amount = each.value.limit_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = each.value.threshold_percent
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = var.notifications_topic_arn != "" ? [var.notifications_topic_arn] : []
    subscriber_email_addresses = try(each.value.emails, [])
  }
}

# DIMENSIONAL/SERVICE monitor: no monitor_specification is required for the
# DIMENSIONAL type (that is only for CUSTOM monitors). It watches every service,
# which covers the always-on service set (Convention 10).
resource "aws_ce_anomaly_monitor" "this" {
  count = var.enable_cost_governance ? 1 : 0

  name              = var.anomaly_monitor_name
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "this" {
  count = var.enable_cost_governance ? 1 : 0

  name             = var.anomaly_subscription_name
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.this[0].arn]

  subscriber {
    type    = "EMAIL"
    address = var.anomaly_email
  }

  # Only alert when the absolute dollar impact of the anomaly is at or above the
  # configured threshold. threshold_expression is optional; the dimension shape
  # (key + match_options + values) is verified against aws provider 6.54.
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }
}

# Activate the B3 tag-policy keys in Cost Explorer / CUR. status is title-case
# "Active"/"Inactive" (NOT upper-case) per aws provider 6.54.
resource "aws_ce_cost_allocation_tag" "this" {
  for_each = var.enable_cost_governance ? toset(var.cost_allocation_tags) : toset([])

  tag_key = each.value
  status  = "Active"
}
