# Resource-assertion tests for the aws/config-org module.
#
# Asserts on configured attributes and for_each/count materialization, which are
# known at plan time under mock_provider. Provider-computed attributes (arns) are
# not asserted on here.

mock_provider "aws" {}

variables {
  recorder_only       = false
  config_role_arn     = "arn:aws:iam::111111111111:role/config"
  aggregator_role_arn = "arn:aws:iam::111111111111:role/config-agg"
  log_archive_bucket  = "ashes-org-log-archive"
  aws_enabled_regions = ["eu-west-2", "eu-west-1"]
}

run "aggregator_and_recorders_materialized" {
  command = plan

  assert {
    condition     = aws_config_configuration_aggregator.org[0].organization_aggregation_source[0].all_regions == true
    error_message = "Org aggregator must aggregate across all Regions"
  }

  assert {
    condition     = length(aws_config_configuration_recorder.this) == 2
    error_message = "A recorder must be materialized for each of the two enabled Regions"
  }

  assert {
    condition     = length(aws_config_delivery_channel.this) == 2
    error_message = "A delivery channel must be materialized for each of the two enabled Regions"
  }
}

run "recorder_only_gates_off_aggregator" {
  command = plan

  variables {
    recorder_only = true
  }

  assert {
    condition     = length(aws_config_configuration_aggregator.org) == 0
    error_message = "Aggregator must be gated off when recorder_only = true"
  }

  assert {
    condition     = length(aws_config_configuration_recorder.this) == 2
    error_message = "Per-Region recorders must still be deployed in recorder_only mode"
  }
}
