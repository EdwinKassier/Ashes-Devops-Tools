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

  # Separation of duties: the key-admin statement grants management actions
  # only — never kms:*, cryptographic operations or CreateGrant.
  assert {
    condition = alltrue([
      for a in ["kms:*", "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:Create*"] :
      !contains(one([for s in jsondecode(aws_kms_key_policy.this.policy).Statement : s if s.Sid == "KeyAdministration"]).Action, a)
    ])
    error_message = "KeyAdministration must not grant kms:*, cryptographic operations or CreateGrant"
  }

  assert {
    condition = alltrue([
      for a in ["kms:Put*", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:Enable*", "kms:Disable*", "kms:RotateKeyOnDemand", "kms:TagResource"] :
      contains(one([for s in jsondecode(aws_kms_key_policy.this.policy).Statement : s if s.Sid == "KeyAdministration"]).Action, a)
    ])
    error_message = "KeyAdministration must retain the management actions needed to avoid key lockout"
  }

  assert {
    condition     = one([for s in jsondecode(aws_kms_key_policy.this.policy).Statement : s if s.Sid == "KeyAdministration"]).Principal.AWS == var.key_admin_arn
    error_message = "KeyAdministration must be granted to key_admin_arn"
  }

  # No usage statement unless key_user_arns is set.
  assert {
    condition     = length([for s in jsondecode(aws_kms_key_policy.this.policy).Statement : s if s.Sid == "KeyUsage"]) == 0
    error_message = "No KeyUsage statement must be rendered when key_user_arns is empty"
  }

  # Protection tag is opt-in.
  assert {
    condition     = !contains(keys(coalesce(aws_kms_key.this.tags, {})), "protected")
    error_message = "the protection tag must be off by default"
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

  # Structural (M6): the CloudTrail grant statement itself (Sid Allow-cloudtrail-*)
  # carries aws:SourceOrgID = org_id AND the EncryptionContext condition — not just
  # the strings appearing somewhere in the document. Catches a refactor that moves
  # either condition onto the wrong statement.
  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key_policy.this.policy).Statement :
      can(regex("cloudtrail", s.Sid))
      && try(s.Condition.StringEquals["aws:SourceOrgID"], null) == var.org_id
      && can(regex("kms:EncryptionContext:aws:cloudtrail:arn", jsonencode(s.Condition)))
    ])
    error_message = "the CloudTrail grant statement must carry aws:SourceOrgID = org_id and the CloudTrail EncryptionContext condition"
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

  # Structural (M6): the SourceOrgID scope is on the ServiceUsage statement itself.
  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key_policy.this.policy).Statement :
      s.Sid == "ServiceUsage" && try(s.Condition.StringEquals["aws:SourceOrgID"], null) == var.org_id
    ])
    error_message = "the ServiceUsage statement must carry aws:SourceOrgID = org_id"
  }

  # No CloudTrail log-service grant means no EncryptionContext condition.
  assert {
    condition     = !can(regex("kms:EncryptionContext:aws:cloudtrail:arn", aws_kms_key_policy.this.policy))
    error_message = "A service-tooling CMK with no log grants must not carry the CloudTrail EncryptionContext condition"
  }
}

run "key_users_separate_from_admin" {
  command = plan

  variables {
    key_user_arns         = ["arn:aws:iam::111122223333:role/LogReader"]
    enable_protection_tag = true
  }

  assert {
    condition     = one([for s in jsondecode(aws_kms_key_policy.this.policy).Statement : s if s.Sid == "KeyUsage"]).Principal.AWS == ["arn:aws:iam::111122223333:role/LogReader"]
    error_message = "KeyUsage must be granted to key_user_arns"
  }

  assert {
    condition     = contains(one([for s in jsondecode(aws_kms_key_policy.this.policy).Statement : s if s.Sid == "KeyUsage"]).Action, "kms:Decrypt")
    error_message = "KeyUsage must grant kms:Decrypt"
  }

  assert {
    condition     = !contains(one([for s in jsondecode(aws_kms_key_policy.this.policy).Statement : s if s.Sid == "KeyUsage"]).Principal.AWS, var.key_admin_arn)
    error_message = "the key admin must not be a key user"
  }

  assert {
    condition     = aws_kms_key.this.tags["protected"] == "true"
    error_message = "enable_protection_tag must tag the key protected = true for the deny-tamper SCP"
  }
}
