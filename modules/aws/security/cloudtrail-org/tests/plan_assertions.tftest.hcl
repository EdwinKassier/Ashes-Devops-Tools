# Resource-assertion tests for the aws/cloudtrail-org module.
#
# Asserts on configured attributes of the trail, which are known at plan time
# under mock_provider. Provider-computed attributes (arn) are deliberately not
# asserted on here. Policies are built with jsonencode, so they are jsondecoded
# and asserted structurally.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  log_archive_bucket = "sra-log-archive-bucket"
  kms_key_arn        = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
}

run "org_trail_is_multi_region_with_log_validation" {
  command = plan

  assert {
    condition     = aws_cloudtrail.org.is_organization_trail == true && aws_cloudtrail.org.is_multi_region_trail == true && aws_cloudtrail.org.enable_log_file_validation == true
    error_message = "Org trail must be an organization trail, multi-Region, and have log-file validation enabled"
  }

  assert {
    condition     = aws_cloudtrail.org.include_global_service_events == true
    error_message = "Org trail must include global service events"
  }

  assert {
    condition     = aws_cloudtrail.org.kms_key_id == var.kms_key_arn && aws_cloudtrail.org.s3_bucket_name == var.log_archive_bucket
    error_message = "Org trail must be CMEK-encrypted with the provided key and deliver to the log-archive bucket"
  }
}

run "s3_write_data_events_by_default" {
  command = plan

  # Advanced selectors replace basic selectors: management events must be
  # selected explicitly alongside the S3 data-event selector.
  assert {
    condition     = length(aws_cloudtrail.org.event_selector) == 0 && length(aws_cloudtrail.org.advanced_event_selector) == 2
    error_message = "Default trail must have exactly two advanced selectors (management + S3 data)"
  }

  assert {
    condition = anytrue([
      for s in aws_cloudtrail.org.advanced_event_selector : anytrue([
        for f in s.field_selector : f.field == "eventCategory" && tolist(f.equals) == tolist(["Management"])
      ])
    ])
    error_message = "Management events must stay selected when advanced selectors are used"
  }

  # CIS AWS 3.8: S3 object writes (readOnly = false).
  assert {
    condition = anytrue([
      for s in aws_cloudtrail.org.advanced_event_selector :
      anytrue([for f in s.field_selector : f.field == "resources.type" && tolist(f.equals) == tolist(["AWS::S3::Object"])]) &&
      anytrue([for f in s.field_selector : f.field == "readOnly" && tolist(f.equals) == tolist(["false"])])
    ])
    error_message = "Default S3 data-event selector must record WriteOnly (readOnly = false) object events"
  }

  # The log-archive bucket is excluded so the trail does not log its own deliveries.
  assert {
    condition = anytrue([
      for s in aws_cloudtrail.org.advanced_event_selector : anytrue([
        for f in s.field_selector : f.field == "resources.ARN" && contains(f.not_starts_with, "arn:aws:s3:::sra-log-archive-bucket/")
      ])
    ])
    error_message = "The log-archive bucket must be excluded from S3 data events by default"
  }

  assert {
    condition = !anytrue([
      for s in aws_cloudtrail.org.advanced_event_selector : anytrue([
        for f in s.field_selector : f.field == "resources.type" && tolist(f.equals) == tolist(["AWS::Lambda::Function"])
      ])
    ])
    error_message = "Lambda data events must be off by default"
  }
}

run "s3_all_data_events_with_lambda" {
  command = plan

  variables {
    cloudtrail_s3_data_events                   = "all"
    enable_lambda_data_events                   = true
    exclude_log_archive_bucket_from_data_events = false
  }

  assert {
    condition     = length(aws_cloudtrail.org.advanced_event_selector) == 3
    error_message = "all + lambda must produce management, S3 and Lambda selectors"
  }

  # "all" = read + write: no readOnly field, and no exclusion when disabled.
  assert {
    condition = !anytrue([
      for s in aws_cloudtrail.org.advanced_event_selector : anytrue([
        for f in s.field_selector : f.field == "readOnly" || f.field == "resources.ARN"
      ])
    ])
    error_message = "all must not filter on readOnly; disabled exclusion must not add a resources.ARN filter"
  }
}

run "s3_read_data_events" {
  command = plan

  variables {
    cloudtrail_s3_data_events = "read"
  }

  assert {
    condition = anytrue([
      for s in aws_cloudtrail.org.advanced_event_selector : anytrue([
        for f in s.field_selector : f.field == "readOnly" && tolist(f.equals) == tolist(["true"])
      ])
    ])
    error_message = "read must record ReadOnly (readOnly = true) object events (CIS 3.9)"
  }
}

run "no_data_events_keeps_management_only" {
  command = plan

  variables {
    cloudtrail_s3_data_events = "none"
  }

  assert {
    condition     = length(aws_cloudtrail.org.event_selector) == 0 && length(aws_cloudtrail.org.advanced_event_selector) == 0
    error_message = "none must leave the trail on its implicit management-events-only behaviour"
  }
}

run "cis_alarms_self_sufficient_by_default" {
  command = plan

  # Make provider-computed ARNs known at plan so the topic/alarm wiring can be
  # asserted.
  override_resource {
    target          = aws_kms_key.cloudwatch[0]
    override_during = plan
    values = {
      arn = "arn:aws:kms:us-east-1:111111111111:key/22222222-2222-2222-2222-222222222222"
    }
  }

  override_resource {
    target          = aws_sns_topic.cis_alarms[0]
    override_during = plan
    values = {
      arn = "arn:aws:sns:us-east-1:111111111111:org-trail-cis-alarms"
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.trail) == 1 && length(aws_iam_role.cloudtrail_cw) == 1
    error_message = "CloudWatch Logs delivery must be on by default"
  }

  # Full CIS section-4 metric-filter set (4.1-4.15).
  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.cis) == 15 && length(aws_cloudwatch_metric_alarm.cis) == 15
    error_message = "All 15 CIS section-4 metric filters + alarms must be created by default"
  }

  assert {
    condition = alltrue([for k in [
      "unauthorized-api-calls", "console-signin-without-mfa", "root-account-usage", "iam-policy-changes",
      "cloudtrail-config-changes", "console-auth-failures", "cmk-disable-or-deletion", "s3-bucket-policy-changes",
      "config-changes", "security-group-changes", "nacl-changes", "network-gateway-changes",
      "route-table-changes", "vpc-changes", "organizations-changes",
    ] : contains(keys(aws_cloudwatch_log_metric_filter.cis), k)])
    error_message = "Every CIS alarm key must have a metric filter"
  }

  # Pattern well-formedness: wrapped in { }, balanced parentheses, and every
  # term uses the $. JSON selector syntax CloudWatch Logs requires.
  assert {
    condition = alltrue([
      for k, f in aws_cloudwatch_log_metric_filter.cis :
      startswith(f.pattern, "{ ") && endswith(f.pattern, " }") &&
      length(regexall("\\(", f.pattern)) == length(regexall("\\)", f.pattern)) &&
      length(regexall("\\$\\.", f.pattern)) > 0 &&
      length(regexall("[{}]", f.pattern)) == 2
    ])
    error_message = "Every CIS metric filter pattern must be a single balanced { ... } JSON filter expression"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_log_metric_filter.cis["console-signin-without-mfa"].pattern, "$.additionalEventData.MFAUsed != \"Yes\"")
    error_message = "CIS 4.2 filter must match console logins without MFA"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_log_metric_filter.cis["cmk-disable-or-deletion"].pattern, "ScheduleKeyDeletion") && strcontains(aws_cloudwatch_log_metric_filter.cis["cmk-disable-or-deletion"].pattern, "DisableKey")
    error_message = "CIS 4.7 filter must match DisableKey and ScheduleKeyDeletion"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_log_metric_filter.cis["organizations-changes"].pattern, "$.eventSource = organizations.amazonaws.com") && strcontains(aws_cloudwatch_log_metric_filter.cis["organizations-changes"].pattern, "LeaveOrganization")
    error_message = "CIS 4.15 filter must match Organizations changes"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_log_metric_filter.cis["unauthorized-api-calls"].pattern, "(($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\")) &&")
    error_message = "CIS 4.1 filter must group the errorCode OR before the noise-exclusion ANDs"
  }

  # Self-sufficient encryption: a dedicated CMK granting the logs service with
  # the log-group encryption-context condition, plus cloudwatch for SNS.
  assert {
    condition     = length(aws_kms_key.cloudwatch) == 1 && aws_kms_key.cloudwatch[0].enable_key_rotation == true
    error_message = "A rotated CloudWatch Logs CMK must be created when none is supplied"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key.cloudwatch[0].policy).Statement :
      s.Sid == "AllowCloudWatchLogs" && startswith(s.Principal.Service, "logs.") && endswith(s.Principal.Service, ".amazonaws.com") &&
      can(regex("^arn:aws:logs:us-east-1:111111111111:log-group:\\*$", s.Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"]))
    ])
    error_message = "CMK policy must grant logs.<region>.amazonaws.com scoped by the log-group encryption context"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key.cloudwatch[0].policy).Statement :
      s.Principal == { Service = "cloudwatch.amazonaws.com" } && contains(keys(s.Condition.StringEquals), "aws:SourceAccount")
    ])
    error_message = "CMK policy must let CloudWatch alarms use the key (encrypted SNS), scoped to the account"
  }

  assert {
    condition     = length(aws_sns_topic.cis_alarms) == 1 && aws_sns_topic.cis_alarms[0].kms_master_key_id == aws_kms_key.cloudwatch[0].arn
    error_message = "A KMS-encrypted CIS alarm SNS topic must be created by default"
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.cis_alarms[0].policy).Statement[0].Principal.Service == "cloudwatch.amazonaws.com" && jsondecode(aws_sns_topic_policy.cis_alarms[0].policy).Statement[0].Action == "sns:Publish"
    error_message = "SNS topic policy must allow CloudWatch alarms to publish"
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.cis : tolist(a.alarm_actions) == tolist(["arn:aws:sns:us-east-1:111111111111:org-trail-cis-alarms"])])
    error_message = "Every CIS alarm must notify the alarm topic"
  }

  assert {
    condition     = jsondecode(aws_iam_role.cloudtrail_cw[0].assume_role_policy).Statement[0].Principal.Service == "cloudtrail.amazonaws.com"
    error_message = "Delivery role must trust CloudTrail only"
  }
}

run "supplied_key_topic_and_exclusions" {
  command = plan

  variables {
    cloudwatch_logs_kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/11111111-1111-1111-1111-111111111111"
    alarm_sns_topic_arn         = "arn:aws:sns:us-east-1:111111111111:secops"
    cis_alarms_excluded         = ["unauthorized-api-calls"]
  }

  assert {
    condition     = length(aws_kms_key.cloudwatch) == 0 && aws_cloudwatch_log_group.trail[0].kms_key_id == var.cloudwatch_logs_kms_key_arn
    error_message = "A supplied CMK must be used instead of creating one"
  }

  assert {
    condition     = length(aws_sns_topic.cis_alarms) == 0 && alltrue([for a in aws_cloudwatch_metric_alarm.cis : tolist(a.alarm_actions) == tolist([var.alarm_sns_topic_arn])])
    error_message = "A supplied topic must be used instead of creating one"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cis) == 14 && !contains(keys(aws_cloudwatch_metric_alarm.cis), "unauthorized-api-calls")
    error_message = "Excluded alarms must not be created"
  }
}

run "subscriptions_attach_to_created_topic" {
  command = plan

  variables {
    alarm_subscriptions = {
      secops = { protocol = "email", endpoint = "secops@example.com" }
    }
  }

  assert {
    condition     = length(aws_sns_topic_subscription.cis_alarms) == 1 && aws_sns_topic_subscription.cis_alarms["secops"].protocol == "email"
    error_message = "alarm_subscriptions must subscribe to the module-created topic"
  }
}

run "cloudwatch_disabled_is_s3_only" {
  command = plan

  variables {
    enable_cloudwatch_logs = false
  }

  assert {
    condition     = aws_cloudtrail.org.cloud_watch_logs_group_arn == null && length(aws_cloudwatch_log_group.trail) == 0 && length(aws_kms_key.cloudwatch) == 0 && length(aws_sns_topic.cis_alarms) == 0 && length(aws_cloudwatch_metric_alarm.cis) == 0
    error_message = "Disabling CloudWatch Logs must remove the log group, CMK, topic and alarms"
  }
}

run "root_key_administration_kept" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key.cloudwatch[0].policy).Statement :
      s.Sid == "KeyAdministration" && s.Action == "kms:*" && endswith(s.Principal.AWS, ":root")
    ])
    error_message = "The account-root kms:* KeyAdministration statement must stay (break-glass path, no orphaned key)."
  }

  assert {
    condition     = !anytrue([for s in jsondecode(aws_kms_key.cloudwatch[0].policy).Statement : s.Sid == "PipelineKeyManagement"])
    error_message = "With no managers supplied there must be no PipelineKeyManagement statement."
  }
}

run "pipeline_manager_statement_grants_refresh_and_rotation" {
  command = plan

  variables {
    cloudwatch_logs_kms_key_manager_arns = ["arn:aws:iam::111111111111:role/tfc-mgmt-aws-security-apply"]
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key.cloudwatch[0].policy).Statement :
      s.Sid == "PipelineKeyManagement" && s.Effect == "Allow" &&
      toset(flatten([s.Principal.AWS])) == toset(["arn:aws:iam::111111111111:role/tfc-mgmt-aws-security-apply"]) &&
      toset(s.Action) == toset([
        "kms:Describe*", "kms:Get*", "kms:List*", "kms:EnableKeyRotation", "kms:UpdateKeyDescription",
        "kms:TagResource", "kms:UntagResource", "kms:CreateAlias", "kms:UpdateAlias", "kms:DeleteAlias",
      ])
    ])
    error_message = "PipelineKeyManagement must grant exactly the refresh/rotation/tag/alias actions to the supplied roles."
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(aws_kms_key.cloudwatch[0].policy).Statement :
      s.Sid == "PipelineKeyManagement" && (contains(s.Action, "kms:*") || contains(s.Action, "kms:PutKeyPolicy") || contains(s.Action, "kms:ScheduleKeyDeletion"))
    ])
    error_message = "PipelineKeyManagement must not grant kms:*, PutKeyPolicy or ScheduleKeyDeletion."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key.cloudwatch[0].policy).Statement :
      s.Sid == "PipelineKeyUseViaServices" && s.Effect == "Allow" &&
      toset(s.Action) == toset(["kms:GenerateDataKey*", "kms:Decrypt"]) &&
      toset(s.Condition.StringEquals["kms:ViaService"]) == toset(["sns.us-east-1.amazonaws.com", "logs.us-east-1.amazonaws.com"])
    ])
    error_message = "Pipeline data-key use must be limited to SNS and Logs via kms:ViaService."
  }

  assert {
    condition     = anytrue([for s in jsondecode(aws_kms_key.cloudwatch[0].policy).Statement : s.Sid == "KeyAdministration"])
    error_message = "KeyAdministration must remain alongside the pipeline statement."
  }
}
