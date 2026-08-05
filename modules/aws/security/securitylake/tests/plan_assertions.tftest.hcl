# Resource-assertion tests for the aws/securitylake module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

variables {
  meta_store_manager_role_arn = "arn:aws:iam::111111111111:role/AmazonSecurityLakeMetaStoreManager"
  kms_key_id                  = "arn:aws:kms:eu-west-2:111111111111:key/abc"
}

run "defaults_create_data_lake_and_log_sources" {
  command = plan

  assert {
    condition     = length(aws_securitylake_data_lake.this) == 1
    error_message = "Data lake must be created when enable_security_lake is true"
  }

  assert {
    condition     = contains(keys(aws_securitylake_aws_log_source.this), "CLOUD_TRAIL_MGMT")
    error_message = "CLOUD_TRAIL_MGMT log source must be present in the default set"
  }

  # No subscriber principal by default, so no subscriber is created.
  assert {
    condition     = length(aws_securitylake_subscriber.this) == 0
    error_message = "Subscriber must not be created when subscriber_principal is empty"
  }
}

run "setting_subscriber_principal_creates_subscriber" {
  command = plan

  variables {
    subscriber_principal = "222222222222"
  }

  assert {
    condition     = length(aws_securitylake_subscriber.this) == 1
    error_message = "Subscriber must be created when subscriber_principal is set"
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enable_security_lake = false
  }

  assert {
    condition     = length(aws_securitylake_data_lake.this) == 0
    error_message = "Data lake must not be created when enable_security_lake is false"
  }

  assert {
    condition     = length(aws_securitylake_aws_log_source.this) == 0
    error_message = "Log sources must not be created when enable_security_lake is false"
  }
}
