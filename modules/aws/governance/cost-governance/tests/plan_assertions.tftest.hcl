# Resource-assertion tests for the aws/cost-governance module.
#
# Uses mock_provider so no AWS credentials are required. Asserts on configured
# attributes and for_each/count keys that ARE known at plan time; the anomaly
# monitor ARN is provider-computed, so monitor_arn_list length is asserted
# structurally (the list has one element regardless of the computed value).

mock_provider "aws" {}

run "enabled_creates_budget_and_anomaly_wiring" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.this["org-monthly"].notification) >= 1
    error_message = "the org-monthly budget must have at least one notification"
  }

  assert {
    condition     = length(aws_ce_anomaly_subscription.this[0].monitor_arn_list) >= 1
    error_message = "the anomaly subscription must reference at least one monitor ARN"
  }

  assert {
    condition     = aws_ce_anomaly_monitor.this[0].monitor_type == "DIMENSIONAL" && aws_ce_anomaly_monitor.this[0].monitor_dimension == "SERVICE"
    error_message = "the anomaly monitor must be a DIMENSIONAL/SERVICE monitor"
  }

  assert {
    condition     = length(aws_ce_cost_allocation_tag.this) == 3
    error_message = "the three default cost-allocation tags must be activated"
  }

  assert {
    condition     = alltrue([for t in aws_ce_cost_allocation_tag.this : t.status == "Active"])
    error_message = "cost-allocation tag status must be title-case Active"
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enable_cost_governance = false
  }

  assert {
    condition     = length(aws_budgets_budget.this) == 0
    error_message = "no budgets must be created when cost governance is disabled"
  }

  assert {
    condition     = length(aws_ce_anomaly_monitor.this) == 0
    error_message = "no anomaly monitor must be created when cost governance is disabled"
  }

  assert {
    condition     = length(aws_ce_cost_allocation_tag.this) == 0
    error_message = "no cost-allocation tags must be activated when cost governance is disabled"
  }
}
