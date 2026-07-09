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
