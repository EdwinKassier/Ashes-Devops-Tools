# Resource-assertion tests for the aws/kms-key module.
#
# The key policy is built with jsonencode() in locals, so it is core-evaluated
# and its content is real (not a mocked data-source .json) under mock_provider.
# That makes the can(regex(...)) content assertions below meaningful.

mock_provider "aws" {}

variables {
  alias                 = "central-logs"
  org_id                = "o-abc123xyz0"
  management_account_id = "111122223333"
  key_admin_arn         = "arn:aws:iam::111122223333:role/KeyAdmin"
}

run "key_and_policy_configured" {
  command = plan

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "Key rotation must be enabled"
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "Default deletion window must be 30 days"
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/central-logs"
    error_message = "Alias name must be prefixed with alias/"
  }

  # CloudTrail service principal is present in a log-service grant.
  assert {
    condition     = can(regex("cloudtrail.amazonaws.com", aws_kms_key_policy.this.policy))
    error_message = "CloudTrail service principal must appear in the key policy"
  }

  # Key-admin statement uses kms:* (asserted as the literal "kms:\\*").
  assert {
    condition     = can(regex("kms:\\*", aws_kms_key_policy.this.policy))
    error_message = "Key-admin statement granting kms:* must be present"
  }

  # aws:SourceOrgID scoping is present on the log-service grants.
  assert {
    condition     = can(regex("aws:SourceOrgID", aws_kms_key_policy.this.policy))
    error_message = "Log-service grants must be scoped by aws:SourceOrgID"
  }

  # CloudTrail's EncryptionContext condition is present.
  assert {
    condition     = can(regex("kms:EncryptionContext:aws:cloudtrail:arn", aws_kms_key_policy.this.policy))
    error_message = "CloudTrail grant must include the EncryptionContext condition"
  }

  # ViaService must be ABSENT — it is never applied to the default (log-service
  # only) configuration, and would deny CloudTrail delivery if present.
  assert {
    condition     = !can(regex("kms:ViaService", aws_kms_key_policy.this.policy))
    error_message = "kms:ViaService must not appear on log-service grants"
  }
}

run "service_principals_grant_present" {
  # A security-tooling CMK grants local AWS services (SNS/SSM/CloudWatch) usage,
  # with no log-service grants at all. The ServiceUsage statement must appear,
  # scoped by aws:SourceOrgID, and must NOT carry the CloudTrail
  # EncryptionContext condition.
  command = plan

  variables {
    alias                  = "security-tooling"
    log_service_principals = []
    service_principals     = ["sns.amazonaws.com", "ssm.amazonaws.com", "cloudwatch.amazonaws.com"]
  }

  assert {
    condition     = can(regex("ServiceUsage", aws_kms_key_policy.this.policy))
    error_message = "ServiceUsage statement must be present when service_principals is set"
  }

  assert {
    condition     = can(regex("sns.amazonaws.com", aws_kms_key_policy.this.policy))
    error_message = "The SNS service principal must appear in the ServiceUsage grant"
  }

  assert {
    condition     = can(regex("aws:SourceOrgID", aws_kms_key_policy.this.policy))
    error_message = "The ServiceUsage grant must be scoped by aws:SourceOrgID"
  }

  # No CloudTrail log-service grant means no EncryptionContext condition.
  assert {
    condition     = !can(regex("kms:EncryptionContext:aws:cloudtrail:arn", aws_kms_key_policy.this.policy))
    error_message = "A service-tooling CMK with no log grants must not carry the CloudTrail EncryptionContext condition"
  }
}
