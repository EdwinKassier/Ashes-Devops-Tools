# Org-wide AWS Config recorders through one service-managed StackSet.
#
# Deploys the customer configuration recorder and its delivery channel to every
# account under target_ou_ids, in every enabled Region, EXCEPT the
# security-tooling account (account_filter_type = DIFFERENCE): security tooling
# keeps its own recorder, which feeds the organization aggregator
# (stages/security, module.config). Auto-deployment gives accounts that join a
# target OU a recorder with no Terraform run.
#
# Constraints this design follows:
#   * Service-managed StackSets never deploy to the management account; the
#     caller (aws-organization) gives it a direct recorder instead.
#   * CloudFormation cannot adopt an existing recorder, and an account/Region
#     holds one customer recorder and one delivery channel. Accounts that still
#     have a Terraform-managed (legacy) recorder fail their stack instance until
#     it is deleted: docs/runbooks/aws-config-recorder-migration.md.
#   * The template creates NO IAM resources. The recorder uses the account's
#     AWS Config service-linked role (AWSServiceRoleForConfig) at its fixed ARN,
#     the role the workload recorder used by default. Accounts that already ran
#     Config have it; for a fresh account Config creates it on first use
#     (validate in the sandbox before relying on it).
#   * Changing deployment_targets (target OUs or the excluded account) forces
#     replacement of the stack instances: every recorder is deleted and
#     recreated, a short recording gap.

locals {
  template = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "AWS Config recorder and delivery channel for the organization (managed by aws-organization)."
    Parameters = {
      IncludeGlobalResourceTypes = {
        Type          = "String"
        AllowedValues = ["true", "false"]
        Default       = "false"
        Description   = "Record global resource types (IAM) in this Region. true only in the home Region, so global items are not duplicated per Region."
      }
    }
    Conditions = {
      RecordGlobalTypes = { "Fn::Equals" = [{ Ref = "IncludeGlobalResourceTypes" }, "true"] }
    }
    Resources = {
      ConfigRecorder = {
        Type = "AWS::Config::ConfigurationRecorder"
        Properties = {
          Name    = var.recorder_name
          RoleARN = { "Fn::Sub" = "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig" }
          RecordingGroup = {
            AllSupported               = true
            IncludeGlobalResourceTypes = { "Fn::If" = ["RecordGlobalTypes", true, false] }
          }
        }
      }
      DeliveryChannel = {
        Type      = "AWS::Config::DeliveryChannel"
        DependsOn = "ConfigRecorder"
        Properties = {
          Name         = var.delivery_channel_name
          S3BucketName = var.log_archive_bucket_name
        }
      }
    }
  })
}

resource "aws_cloudformation_stack_set" "this" {
  name             = var.stack_set_name
  description      = "AWS Config recorder and delivery channel in every member account except security tooling."
  permission_model = "SERVICE_MANAGED"
  call_as          = var.call_as
  template_body    = local.template

  parameters = {
    IncludeGlobalResourceTypes = "false"
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  managed_execution {
    active = true
  }

  operation_preferences {
    failure_tolerance_percentage = var.migration_failure_tolerance_percentage
    max_concurrent_percentage    = var.max_concurrent_percentage
    region_concurrency_type      = "PARALLEL"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [administration_role_arn]
  }
}

# One instance set per Region. The home Region records global resource types.
resource "aws_cloudformation_stack_set_instance" "this" {
  for_each = toset(var.aws_enabled_regions)

  stack_set_name            = aws_cloudformation_stack_set.this.name
  stack_set_instance_region = each.value
  call_as                   = var.call_as
  retain_stack              = false

  parameter_overrides = {
    IncludeGlobalResourceTypes = each.value == var.home_region ? "true" : "false"
  }

  # Changing these forces replacement of the instances (recorders recreated).
  deployment_targets {
    organizational_unit_ids = var.target_ou_ids
    account_filter_type     = "DIFFERENCE"
    accounts                = [var.security_tooling_account_id]
  }

  operation_preferences {
    # 0 for routine runs. The migration pass sets 100 so the instances that
    # fail in accounts still holding a legacy recorder do not fail the apply.
    failure_tolerance_percentage = var.migration_failure_tolerance_percentage
    max_concurrent_percentage    = var.max_concurrent_percentage
    concurrency_mode             = "SOFT_FAILURE_TOLERANCE"
  }
}
