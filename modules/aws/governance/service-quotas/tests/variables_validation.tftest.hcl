# Variable validation tests for the aws/service-quotas module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "positive_values_accepted" {
  # Quota-increase entries with positive requested values must pass.
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
  }
}

run "empty_map_accepted" {
  # The empty default map must pass (no requests to validate).
  command = plan

  variables {
    enable_service_quotas = false
    quota_increases       = {}
  }
}

run "non_positive_value_rejected" {
  # A zero requested value is meaningless for a quota request and must be
  # rejected.
  command = plan

  variables {
    enable_service_quotas = true
    quota_increases = {
      bad-entry = {
        service_code = "ec2"
        quota_code   = "L-1216C47A"
        value        = 0
      }
    }
  }

  expect_failures = [var.quota_increases]
}
