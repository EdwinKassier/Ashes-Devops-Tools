# Resource-assertion tests for the aws/incident-response module.
#
# The aws provider is mocked; the archive provider is NOT mocked and runs for
# real (init fetches it), packaging files/isolate.py so source_code_hash and the
# Lambda filename resolve. Assertions read plan-known configured attributes.

mock_provider "aws" {
  # The Lambda's role must be a valid ARN; give the mocked IAM role one so the
  # apply-command run below can materialize the Lambda and its event target.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/ir-mock"
    }
  }

  # Likewise give the Lambda a valid ARN so the event target (which requires a
  # valid ARN) can be created on apply.
  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:111111111111:function:ir-isolate"
    }
  }
}

variables {
  forensics_account_id = "333333333333"
  org_id               = "o-abc123def0"
}

run "guardduty_isolation_and_forensics_wired" {
  # apply so the mock provider materializes computed values (the target arn is
  # the Lambda's arn, which is only known after apply).
  command = apply

  assert {
    condition     = can(regex("aws.guardduty", aws_cloudwatch_event_rule.guardduty_high[0].event_pattern))
    error_message = "EventBridge rule must match the aws.guardduty source"
  }

  assert {
    condition     = aws_cloudwatch_event_target.isolate[0].arn != ""
    error_message = "EventBridge target must point at the isolation Lambda ARN"
  }

  assert {
    condition     = can(regex("aws:PrincipalOrgID", aws_iam_role.forensics_snapshot[0].assume_role_policy))
    error_message = "Forensics role trust must be scoped by aws:PrincipalOrgID"
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enable_incident_response = false
    forensics_account_id     = ""
    org_id                   = ""
  }

  assert {
    condition     = length(aws_lambda_function.isolate) == 0
    error_message = "No isolation Lambda must be created when incident response is disabled"
  }

  assert {
    condition     = length(aws_iam_role.forensics_snapshot) == 0
    error_message = "No forensics role must be created when incident response is disabled"
  }
}
