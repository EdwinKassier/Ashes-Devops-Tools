# Variable validation tests for the aws/data/rds-aurora module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation, so these pass regardless of
# mock provider behaviour.

mock_provider "aws" {}

# Base set of valid required variables, shared by every run.
variables {
  name               = "orders-db"
  kms_key_id         = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  subnet_ids         = ["subnet-0aaa", "subnet-0bbb"]
  security_group_ids = ["sg-0aaa"]
}

run "defaults_accepted" {
  command = plan
}

run "missing_cmek_rejected" {
  command = plan

  # The default AWS-managed key is not allowed — a non-CMEK value must fail.
  variables {
    kms_key_id = "alias/aws/rds"
  }

  expect_failures = [var.kms_key_id]
}

run "zero_instances_rejected" {
  command = plan

  variables {
    instance_count = 0
  }

  expect_failures = [var.instance_count]
}

run "password_required_when_not_managed" {
  command = plan

  # When RDS is not managing the password, one must be supplied.
  variables {
    manage_master_user_password = false
    master_password             = null
  }

  expect_failures = [var.master_password]
}

run "explicit_password_accepted_when_not_managed" {
  command = plan

  variables {
    manage_master_user_password = false
    master_password             = "aVerySecretValue123!"
  }
}

run "single_subnet_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-0aaa"]
  }

  expect_failures = [var.subnet_ids]
}

run "serverless_v2_accepted" {
  command = plan

  variables {
    enable_serverless_v2       = true
    serverless_v2_min_capacity = 0.5
    serverless_v2_max_capacity = 8
  }
}
