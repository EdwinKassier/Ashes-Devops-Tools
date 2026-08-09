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
        usage_metric = {
          service  = "EC2"
          class    = "Standard/OnDemand"
          type     = "Resource"
          resource = "vCPU"
        }
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

  # Audit A2: the AWS/Usage alarm must carry the required dimensions, else it
  # can never leave INSUFFICIENT_DATA.
  assert {
    condition = (
      aws_cloudwatch_metric_alarm.usage["ec2-standard-vcpus"].dimensions["Service"] == "EC2" &&
      aws_cloudwatch_metric_alarm.usage["ec2-standard-vcpus"].dimensions["Resource"] == "vCPU"
    )
    error_message = "The usage alarm must set the AWS/Usage Service/Resource dimensions"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.usage["ec2-standard-vcpus"].treat_missing_data == "notBreaching"
    error_message = "The usage alarm must treat missing data as notBreaching"
  }
}

run "quota_without_usage_metric_gets_request_but_no_alarm" {
  command = plan

  variables {
    enable_service_quotas = true
    quota_increases = {
      ec2-standard-vcpus = {
        service_code = "ec2"
        quota_code   = "L-1216C47A"
        value        = 256
        # no usage_metric -> request filed, but no (inert) alarm
      }
    }
  }

  assert {
    condition     = length(aws_servicequotas_service_quota.this) == 1
    error_message = "The quota request must still be filed without usage_metric"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.usage) == 0
    error_message = "No alarm must be created for an entry lacking usage_metric dimensions"
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
