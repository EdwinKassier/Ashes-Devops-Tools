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

  # The Lambda permission validates its source_arn (the event-rule ARN), so give
  # the mocked event rule a valid ARN too.
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:us-east-1:111111111111:rule/ir-guardduty-high-severity"
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

  # The trust is scoped by principal-side keys only. aws:SourceAccount and
  # aws:SourceOrgID are set only on service-principal calls, so a role-to-role
  # AssumeRole conditioned on them would always be denied.
  assert {
    condition = (
      jsondecode(aws_iam_role.forensics_snapshot[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:PrincipalOrgID"] == "o-abc123def0" &&
      jsondecode(aws_iam_role.forensics_snapshot[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:PrincipalAccount"] == "333333333333" &&
      !can(regex("aws:Source", aws_iam_role.forensics_snapshot[0].assume_role_policy))
    )
    error_message = "Forensics role trust must be scoped by aws:PrincipalOrgID and aws:PrincipalAccount, never by aws:Source* keys"
  }

  # EventBridge must be granted permission to invoke the Lambda.
  assert {
    condition     = aws_lambda_permission.eventbridge[0].principal == "events.amazonaws.com"
    error_message = "EventBridge must have lambda:InvokeFunction permission on the isolation Lambda"
  }

  assert {
    condition     = aws_lambda_permission.eventbridge[0].source_arn == aws_cloudwatch_event_rule.guardduty_high[0].arn
    error_message = "The Lambda permission must be scoped to the GuardDuty EventBridge rule ARN"
  }

  # With no quarantine_vpc_id and no forensics_kms_key_arn, those optional
  # resources are gated off.
  assert {
    condition     = length(aws_security_group.quarantine) == 0
    error_message = "No quarantine SG must be created when quarantine_vpc_id is unset"
  }

  assert {
    condition     = length(aws_iam_role_policy.forensics_kms) == 0
    error_message = "No forensics KMS policy must be created when forensics_kms_key_arn is unset"
  }
}

run "quarantine_sg_and_forensics_kms_created" {
  # With a VPC id and forensics CMK supplied, the deny-all quarantine SG and the
  # forensics KMS role policy are created.
  command = plan

  variables {
    quarantine_vpc_id     = "vpc-0abc123def4567890"
    forensics_kms_key_arn = "arn:aws:kms:eu-west-2:333333333333:key/forensics-0000"
  }

  assert {
    condition     = length(aws_security_group.quarantine) == 1
    error_message = "A quarantine SG must be created when quarantine_vpc_id is set"
  }

  # The SG is created in the supplied VPC. Deny-all is achieved by declaring no
  # ingress/egress rules at all (implicit deny-all); ingress/egress are computed
  # and unknown at plan, so we assert the VPC placement here.
  assert {
    condition     = aws_security_group.quarantine[0].vpc_id == "vpc-0abc123def4567890"
    error_message = "The quarantine SG must be created in the supplied VPC"
  }

  assert {
    condition     = length(aws_iam_role_policy.forensics_kms) == 1
    error_message = "A forensics KMS role policy must be created when forensics_kms_key_arn is set"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.forensics_kms[0].policy).Statement[0].Condition.StringEquals["aws:PrincipalOrgID"] == "o-abc123def0" &&
      !can(regex("aws:Source", aws_iam_role_policy.forensics_kms[0].policy))
    )
    error_message = "The forensics KMS grant must be scoped by aws:PrincipalOrgID, never by aws:SourceOrgID"
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

  assert {
    condition     = length(aws_lambda_permission.eventbridge) == 0
    error_message = "No Lambda permission must be created when incident response is disabled"
  }
}

# Boundary propagation (tfc-oidc-baseline): both IR roles carry
# permissions_boundary_arn so the security-tooling tfc-apply role may create them.
run "ir_roles_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/tfc-apply-boundary"
  }

  assert {
    condition     = aws_iam_role.isolation_lambda[0].permissions_boundary == "arn:aws:iam::123456789012:policy/tfc-apply-boundary" && aws_iam_role.forensics_snapshot[0].permissions_boundary == "arn:aws:iam::123456789012:policy/tfc-apply-boundary"
    error_message = "The isolation Lambda and forensics snapshot-share roles must carry permissions_boundary_arn."
  }
}

run "module_tags_applied" {
  command = apply

  variables {
    tags = { Owner = "test" }
  }

  assert {
    condition     = aws_iam_role.forensics_snapshot[0].tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_iam_role.forensics_snapshot"
  }
}

run "archive_written_under_root" {
  command = plan

  assert {
    condition     = data.archive_file.isolate[0].output_path == "${path.root}/.terraform/tmp/incident-response-isolate.zip"
    error_message = "The Lambda archive must be written under path.root/.terraform/tmp, not into the module directory"
  }

  assert {
    condition     = aws_lambda_function.isolate[0].filename == data.archive_file.isolate[0].output_path
    error_message = "The Lambda must deploy the archive written under path.root"
  }
}
