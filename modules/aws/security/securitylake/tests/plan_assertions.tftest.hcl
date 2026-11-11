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

run "module_tags_applied" {
  command = plan

  variables {
    tags = { Owner = "test" }
  }

  assert {
    condition     = aws_securitylake_data_lake.this[0].tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_securitylake_data_lake.this"
  }
}

# The provider allows one configuration block per data lake: each extra Region
# gets its own lake in that Region, with its own regional key.
run "one_data_lake_per_region" {
  command = plan

  variables {
    aws_enabled_regions           = ["eu-west-2", "eu-west-1", "us-east-1"]
    additional_region_kms_key_ids = { "eu-west-1" = "arn:aws:kms:eu-west-1:111111111111:key/def" }
  }

  assert {
    condition     = length(aws_securitylake_data_lake.this[0].configuration) == 1 && aws_securitylake_data_lake.this[0].configuration[0].region == "eu-west-2"
    error_message = "the home lake has one configuration block, for the first enabled Region."
  }

  assert {
    condition = (
      toset(keys(aws_securitylake_data_lake.additional)) == toset(["eu-west-1", "us-east-1"]) &&
      aws_securitylake_data_lake.additional["eu-west-1"].region == "eu-west-1" &&
      aws_securitylake_data_lake.additional["eu-west-1"].configuration[0].encryption_configuration[0].kms_key_id == "arn:aws:kms:eu-west-1:111111111111:key/def" &&
      aws_securitylake_data_lake.additional["us-east-1"].configuration[0].encryption_configuration[0].kms_key_id == "S3_MANAGED"
    )
    error_message = "each extra Region gets its own lake in that Region, encrypted with its regional key or S3_MANAGED."
  }
}

run "single_region_has_no_additional_lake" {
  command = plan

  assert {
    condition     = length(aws_securitylake_data_lake.additional) == 0
    error_message = "with one enabled Region only the home lake exists."
  }
}
