# Plan assertions for the aws/security/config-recorder-stackset module.
#
# One service-managed StackSet deploys the customer Config recorder and
# delivery channel to every account under the target OUs except security
# tooling (which keeps its own aggregator recorder). The template creates no
# IAM resources and records global resource types in the home Region only.

mock_provider "aws" {}

variables {
  target_ou_ids               = ["r-abcd"]
  security_tooling_account_id = "222222222222"
  aws_enabled_regions         = ["eu-west-2", "eu-west-1", "us-east-1"]
  home_region                 = "eu-west-2"
  log_archive_bucket_name     = "acme-org-log-archive"
  tags                        = { Component = "config" }
}

run "targets_ous_excluding_security_tooling" {
  command = plan

  assert {
    condition     = aws_cloudformation_stack_set.this.permission_model == "SERVICE_MANAGED"
    error_message = "the StackSet must be service-managed (organization deployment)"
  }

  assert {
    condition = (
      aws_cloudformation_stack_set.this.auto_deployment[0].enabled == true &&
      aws_cloudformation_stack_set.this.auto_deployment[0].retain_stacks_on_account_removal == false
    )
    error_message = "auto-deployment must be on and must not retain stacks on account removal"
  }

  assert {
    condition     = length(aws_cloudformation_stack_set_instance.this) == 3
    error_message = "one stack instance per enabled Region"
  }

  assert {
    condition = alltrue([
      for r, i in aws_cloudformation_stack_set_instance.this :
      tolist(i.deployment_targets[0].organizational_unit_ids) == tolist(["r-abcd"]) &&
      i.deployment_targets[0].account_filter_type == "DIFFERENCE" &&
      tolist(i.deployment_targets[0].accounts) == tolist(["222222222222"]) &&
      i.stack_set_instance_region == r
    ])
    error_message = "every instance must target the OUs minus the security-tooling account (DIFFERENCE filter)"
  }

  assert {
    condition = alltrue([
      for i in aws_cloudformation_stack_set_instance.this :
      i.operation_preferences[0].failure_tolerance_percentage == 0
    ])
    error_message = "the routine failure tolerance must be 0"
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.tags["Component"] == "config"
    error_message = "var.tags must be applied to the StackSet"
  }
}

run "migration_tolerance_feeds_operation_preferences" {
  command = plan

  variables {
    migration_failure_tolerance_percentage = 100
  }

  assert {
    condition = alltrue([
      for i in aws_cloudformation_stack_set_instance.this :
      i.operation_preferences[0].failure_tolerance_percentage == 100
    ])
    error_message = "migration_failure_tolerance_percentage must feed operation_preferences.failure_tolerance_percentage"
  }
}

run "global_types_home_region_only" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_cloudformation_stack_set.this.template_body).Conditions.IsHomeRegion["Fn::Equals"][0].Ref == "AWS::Region" &&
      jsondecode(aws_cloudformation_stack_set.this.template_body).Conditions.IsHomeRegion["Fn::Equals"][1] == "eu-west-2" &&
      jsondecode(aws_cloudformation_stack_set.this.template_body).Resources.ConfigRecorder.Properties.RecordingGroup.IncludeGlobalResourceTypes["Fn::If"][0] == "IsHomeRegion"
    )
    error_message = "IncludeGlobalResourceTypes must be gated on AWS::Region == home_region inside the template"
  }

  # No per-instance overrides: auto-deployed accounts must get the same result.
  assert {
    condition = (
      !can(jsondecode(aws_cloudformation_stack_set.this.template_body).Parameters) &&
      alltrue([for i in aws_cloudformation_stack_set_instance.this : length(coalesce(i.parameter_overrides, {})) == 0])
    )
    error_message = "the template takes no parameters and the instances carry no parameter overrides"
  }
}

# PutConfigurationRecorder / PutDeliveryChannel are upserts by name: the
# StackSet must never share the legacy config-org names.
run "names_differ_from_legacy_config_org" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_cloudformation_stack_set.this.template_body).Resources.ConfigRecorder.Properties.Name == "org-stackset-recorder" &&
      jsondecode(aws_cloudformation_stack_set.this.template_body).Resources.DeliveryChannel.Properties.Name == "org-stackset-delivery"
    )
    error_message = "the StackSet recorder / channel defaults must be org-stackset-recorder / org-stackset-delivery"
  }
}

run "template_has_no_iam_resources" {
  command = plan

  assert {
    condition = length([
      for k, r in jsondecode(aws_cloudformation_stack_set.this.template_body).Resources : k if startswith(r.Type, "AWS::IAM::")
    ]) == 0
    error_message = "the template must create no IAM resources"
  }

  assert {
    condition     = length(coalesce(aws_cloudformation_stack_set.this.capabilities, [])) == 0
    error_message = "with no IAM resources the StackSet needs no IAM capabilities"
  }

  assert {
    condition = (
      toset([for r in jsondecode(aws_cloudformation_stack_set.this.template_body).Resources : r.Type]) ==
      toset(["AWS::Config::ConfigurationRecorder", "AWS::Config::DeliveryChannel"])
    )
    error_message = "the template must hold exactly the recorder and the delivery channel"
  }

  assert {
    condition     = jsondecode(aws_cloudformation_stack_set.this.template_body).Resources.ConfigRecorder.Properties.RoleARN["Fn::Sub"] == "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
    error_message = "the recorder must use the account's Config service-linked role, the workload recorder's default role"
  }

  assert {
    condition = (
      jsondecode(aws_cloudformation_stack_set.this.template_body).Resources.DeliveryChannel.Properties.S3BucketName == "acme-org-log-archive" &&
      jsondecode(aws_cloudformation_stack_set.this.template_body).Resources.DeliveryChannel.DependsOn == "ConfigRecorder"
    )
    error_message = "delivery must go to the log-archive bucket, after the recorder exists"
  }

  assert {
    condition     = jsondecode(aws_cloudformation_stack_set.this.template_body).Resources.ConfigRecorder.Properties.RecordingGroup.AllSupported == true
    error_message = "the recorder must record every supported resource type"
  }
}
