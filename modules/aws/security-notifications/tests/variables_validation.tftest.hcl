# Variable validation tests for the aws/security-notifications module.

mock_provider "aws" {}

run "valid_inputs_accepted" {
  command = plan

  variables {
    kms_key_id               = "arn:aws:kms:eu-west-2:111111111111:key/abc"
    notification_subscribers = { ops = { protocol = "email", endpoint = "secops@example.com" } }
  }
}

run "enabled_without_subscribers_rejected" {
  # When enabled, an empty subscriber map must trip the validation so findings
  # are never fired into a void.
  command = plan

  variables {
    kms_key_id               = "arn:aws:kms:eu-west-2:111111111111:key/abc"
    notification_subscribers = {}
  }

  expect_failures = [var.notification_subscribers]
}
