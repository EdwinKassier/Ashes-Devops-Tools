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

run "dashboard_renders_configured_widgets" {
  command = plan

  variables {
    enable_dashboard = true
    dashboard_widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          region  = "eu-west-1"
          title   = "CPU"
          metrics = [["AWS/EC2", "CPUUtilization"]]
        }
      }
    ]
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.this[0].dashboard_body).widgets) == 1
    error_message = "The dashboard body must carry the one configured widget"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.this[0].dashboard_body).widgets[0].type == "metric"
    error_message = "The configured widget must be rendered, not the placeholder"
  }
}

run "dashboard_placeholder_when_no_widgets" {
  command = plan

  variables {
    enable_dashboard = true
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.this[0].dashboard_body).widgets[0].type == "text"
    error_message = "An empty dashboard_widgets list must render the single text placeholder"
  }
}

run "dashboard_renders_mixed_widget_shapes" {
  command = plan

  variables {
    enable_dashboard = true
    dashboard_widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Service health"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          region  = "eu-west-1"
          title   = "CPU"
          metrics = [["AWS/EC2", "CPUUtilization"]]
        }
      }
    ]
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.this[0].dashboard_body).widgets) == 2
    error_message = "Widgets of different shapes (text and metric) must render side by side"
  }
}
