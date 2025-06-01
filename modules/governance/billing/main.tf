resource "aws_sns_topic" "budget_alerts" {
  name = "budget-alerts"
  tags = var.tags
}

resource "aws_sns_topic_policy" "budget_alerts" {
  arn = aws_sns_topic.budget_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSBudgetsSNSPublishingPermissions"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.budget_alerts.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "budget_alerts_email" {
  count     = length(var.email_recipients)
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.email_recipients[count.index]
}

resource "aws_budgets_budget" "monthly" {
  name              = "monthly-budget"
  budget_type       = "COST"
  limit_amount      = var.monthly_budget_limit
  limit_unit        = "USD"
  time_period_start = "2024-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.alert_threshold
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.alert_threshold
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  cost_filters = {
    "TagKeyValue" = "user:Environment$Dev"
  }

  tags = var.tags
} 