# Variable validation tests for the ops/cloudwatch module (mock_provider — no creds).

mock_provider "aws" {}

variables {
  name_prefix = "prod"
}

run "accepts_empty_defaults" {
  command = plan
}

run "rejects_bad_comparison_operator" {
  command = plan

  expect_failures = [var.alarms]

  variables {
    alarms = {
      bad = { namespace = "AWS/EC2", metric_name = "CPUUtilization", comparison_operator = "EqualTo", threshold = 1 }
    }
  }
}

run "rejects_bad_statistic" {
  command = plan

  expect_failures = [var.alarms]

  variables {
    alarms = {
      bad = { namespace = "AWS/EC2", metric_name = "CPUUtilization", statistic = "Median", comparison_operator = "GreaterThanThreshold", threshold = 1 }
    }
  }
}

run "rejects_zero_period" {
  command = plan

  expect_failures = [var.alarms]

  variables {
    alarms = {
      bad = { namespace = "AWS/EC2", metric_name = "CPUUtilization", comparison_operator = "GreaterThanThreshold", threshold = 1, period = 0 }
    }
  }
}

run "rejects_bad_name_prefix" {
  command = plan

  expect_failures = [var.name_prefix]

  variables {
    name_prefix = "bad prefix!"
  }
}
