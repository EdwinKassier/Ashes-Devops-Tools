# Plan assertions for the ops/cloudwatch module (mock_provider — no creds).

mock_provider "aws" {}

variables {
  name_prefix = "prod"
  alarms = {
    high-cpu = {
      namespace           = "AWS/EC2"
      metric_name         = "CPUUtilization"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
    }
  }
}

run "alarm_wired_from_input" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 1
    error_message = "Expected one alarm to be planned"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["high-cpu"].comparison_operator == "GreaterThanThreshold"
    error_message = "comparison_operator must propagate from input"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["high-cpu"].threshold == 80
    error_message = "threshold must propagate from input"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["high-cpu"].treat_missing_data == "notBreaching"
    error_message = "treat_missing_data must default to notBreaching"
  }
}

run "sns_topic_gated_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_sns_topic.this) == 0
    error_message = "SNS topic must not be created when create_sns_topic = false"
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.this) == 0
    error_message = "Dashboard must not be created when enable_dashboard = false"
  }
}

run "sns_and_dashboard_created_when_enabled" {
  command = plan

  variables {
    create_sns_topic = true
    enable_dashboard = true
  }

  assert {
    condition     = length(aws_sns_topic.this) == 1
    error_message = "SNS topic must be created when create_sns_topic = true"
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.this) == 1
    error_message = "Dashboard must be created when enable_dashboard = true"
  }
}
