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

  # Global resource types are recorded ONLY by the home-Region recorder.
  assert {
    condition     = aws_config_configuration_recorder.this["eu-west-2"].recording_group[0].include_global_resource_types == true
    error_message = "Home-Region recorder must record global resource types"
  }

  assert {
    condition     = aws_config_configuration_recorder.this["eu-west-1"].recording_group[0].include_global_resource_types == false
    error_message = "Non-home-Region recorders must NOT record global resource types"
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

# Default identities: no role ARNs supplied -> the recorder uses the Config
# service-linked role (created here) and the org aggregator gets its own role.
run "default_roles_created" {
  command = plan

  variables {
    config_role_arn     = null
    aggregator_role_arn = null
    account_id          = "222222222222"
  }

  assert {
    condition     = length(aws_iam_service_linked_role.config) == 1 && aws_iam_service_linked_role.config[0].aws_service_name == "config.amazonaws.com"
    error_message = "With config_role_arn = null the AWSServiceRoleForConfig service-linked role must be created."
  }

  assert {
    condition     = length(aws_iam_role.aggregator) == 1 && jsondecode(aws_iam_role.aggregator[0].assume_role_policy).Statement[0].Principal.Service == "config.amazonaws.com"
    error_message = "With aggregator_role_arn = null an aggregator role trusted by config.amazonaws.com must be created."
  }

  assert {
    condition     = endswith(aws_iam_role_policy_attachment.aggregator[0].policy_arn, ":iam::aws:policy/service-role/AWSConfigRoleForOrganizations")
    error_message = "The aggregator role must carry AWSConfigRoleForOrganizations."
  }

  assert {
    condition     = aws_config_configuration_recorder.this["eu-west-2"].role_arn == "arn:aws:iam::222222222222:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
    error_message = "The recorder must use the account's AWSServiceRoleForConfig ARN."
  }
}

run "existing_service_linked_role_referenced" {
  command = plan

  variables {
    config_role_arn            = null
    create_service_linked_role = false
  }

  override_data {
    target = data.aws_caller_identity.current[0]
    values = { account_id = "222222222222" }
  }

  assert {
    condition     = length(aws_iam_service_linked_role.config) == 0 && aws_config_configuration_recorder.this["eu-west-2"].role_arn == "arn:aws:iam::222222222222:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
    error_message = "With create_service_linked_role = false the recorder must reference the existing SLR by its well-known ARN."
  }
}

run "explicit_roles_create_nothing" {
  command = plan

  assert {
    condition     = length(aws_iam_service_linked_role.config) == 0 && length(aws_iam_role.aggregator) == 0 && aws_config_configuration_recorder.this["eu-west-1"].role_arn == "arn:aws:iam::111111111111:role/config"
    error_message = "Explicit role ARNs must be used as-is and no role created."
  }
}

# Boundary propagation (tfc-oidc-baseline): the module-created org aggregator
# role carries permissions_boundary_arn.
run "aggregator_role_permissions_boundary" {
  command = plan

  variables {
    aggregator_role_arn      = null
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/tfc-apply-boundary"
  }

  assert {
    condition     = aws_iam_role.aggregator[0].permissions_boundary == "arn:aws:iam::123456789012:policy/tfc-apply-boundary"
    error_message = "The org aggregator role must carry permissions_boundary_arn."
  }
}
