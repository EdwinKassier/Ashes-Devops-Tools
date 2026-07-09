# Resource-assertion tests for the aws/security-notifications module.
#
# The aws provider is mocked. The SNS topic is given a valid ARN so the topic
# policy, subscriptions, and event targets (which all reference the topic ARN)
# can materialize on apply.

mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-west-2:111111111111:security-notifications"
    }
  }
}

variables {
  kms_key_id               = "arn:aws:kms:eu-west-2:111111111111:key/abc"
  notification_subscribers = { ops = { protocol = "email", endpoint = "secops@example.com" } }
}

run "topic_rules_subscription_and_automation_wired" {
  # apply so the mocked topic ARN materializes for the targets and subscription.
  command = apply

  assert {
    condition     = length(aws_sns_topic_subscription.this) >= 1
    error_message = "At least one SNS subscription must be created when enabled"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.this) >= 4
    error_message = "At least four detective EventBridge rules must be created"
  }

  assert {
    condition     = length(aws_securityhub_automation_rule.suppress_known) == 1
    error_message = "The Security Hub automation rule must be created when enabled"
  }

  # With no CloudTrail log group supplied, the break-glass metric alarm path is
  # gated off — only the always-on EventBridge rule provides break-glass cover.
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.break_glass) == 0
    error_message = "The break-glass metric alarm must be gated off without a CloudTrail log group"
  }

  # The always-on EventBridge break-glass rule is present regardless.
  assert {
    condition     = contains(keys(aws_cloudwatch_event_rule.this), "break-glass-use")
    error_message = "The always-on break-glass EventBridge rule must be present"
  }
}

run "break_glass_alarm_created_with_log_group" {
  # With the CloudTrail log group AND break-glass role ARN supplied, the metric
  # filter + CloudWatch metric alarm are created and the alarm actions target
  # the SNS topic.
  command = apply

  variables {
    cloudtrail_log_group_name = "aws-cloudtrail-logs-org"
    break_glass_role_arn      = "arn:aws:iam::111111111111:role/break-glass"
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.break_glass) == 1
    error_message = "A break-glass metric filter must be created when the CloudTrail log group is set"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.break_glass) == 1
    error_message = "A break-glass metric alarm must be created when the CloudTrail log group is set"
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.break_glass[0].alarm_actions, aws_sns_topic.this[0].arn)
    error_message = "The break-glass alarm must notify the SNS topic"
  }

  assert {
    condition     = can(regex("break-glass", aws_cloudwatch_log_metric_filter.break_glass[0].pattern))
    error_message = "The metric filter pattern must match the break-glass role ARN"
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enable_security_notifications = false
    notification_subscribers      = {}
  }

  assert {
    condition     = length(aws_sns_topic.this) == 0
    error_message = "No SNS topic must be created when disabled"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.this) == 0
    error_message = "No EventBridge rules must be created when disabled"
  }
}
