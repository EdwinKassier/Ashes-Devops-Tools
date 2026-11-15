# Variable validation tests for the aws/security-notifications module.

mock_provider "aws" {}

run "valid_inputs_accepted" {
  command = plan

  variables {
    kms_key_id               = "arn:aws:kms:eu-west-2:111111111111:key/abc"
    notification_subscribers = { ops = { protocol = "email", endpoint = "secops@example.com" } }
  }
}

run "enabled_without_subscribers_accepted" {
  # An empty subscriber map plans (the topic exists, no subscription); the
  # aws-security root decides whether that is allowed (CMP-6).
  command = plan

  variables {
    kms_key_id               = "arn:aws:kms:eu-west-2:111111111111:key/abc"
    notification_subscribers = {}
  }

  assert {
    condition     = length(aws_sns_topic.this) == 1 && length(aws_sns_topic_subscription.this) == 0
    error_message = "an empty subscriber map must create the topic and no subscription."
  }
}

run "unknown_protocol_rejected" {
  command = plan

  variables {
    kms_key_id               = "arn:aws:kms:eu-west-2:111111111111:key/abc"
    notification_subscribers = { ops = { protocol = "pager", endpoint = "secops" } }
  }

  expect_failures = [var.notification_subscribers]
}
