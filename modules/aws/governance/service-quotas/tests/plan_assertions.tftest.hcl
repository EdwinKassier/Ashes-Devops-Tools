# Resource-assertion tests for the aws/service-quotas module.
# The aws provider is mocked; assertions read configured attributes.

mock_provider "aws" {}

run "enabled_creates_request_and_alarm" {
  command = plan

  variables {
    enable_service_quotas = true
    quota_increases = {
      ec2-standard-vcpus = {
        service_code = "ec2"
        quota_code   = "L-1216C47A"
        value        = 256
      }
    }
    notifications_topic_arn = "arn:aws:sns:eu-west-2:111111111111:sec"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.usage) == 1
    error_message = "Exactly one usage alarm must be created for the single quota entry"
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.usage["ec2-standard-vcpus"].alarm_actions, "arn:aws:sns:eu-west-2:111111111111:sec")
    error_message = "The usage alarm must route to the security-notifications SNS topic"
  }
}

run "disabled_creates_nothing" {
  command = plan

  # Defaults: enable_service_quotas = false.
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.usage) == 0
    error_message = "No usage alarms must be created when the module is disabled"
  }

  assert {
    condition     = length(aws_servicequotas_service_quota.this) == 0
    error_message = "No quota requests must be created when the module is disabled"
  }
}
