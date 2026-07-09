# Resource-assertion tests for the aws/secrets-baseline module.
#
# Asserts on for_each cardinality (known at plan time under mock_provider) and
# on the rendered resource policy JSON. Provider-computed attributes (arns) are
# deliberately not asserted on.

mock_provider "aws" {}

run "enabled_creates_secret_policy_and_rotation" {
  command = plan

  variables {
    enable_secrets_baseline = true
    org_id                  = "o-exampleorgid"
    secrets = {
      "app/api-key" = {
        rotation_lambda_arn = "arn:aws:lambda:us-east-1:111122223333:function:rotate"
        rotation_days       = 30
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.this) == 1
    error_message = "One secret must be created"
  }

  assert {
    condition     = can(regex("aws:PrincipalOrgID", aws_secretsmanager_secret_policy.this["app/api-key"].policy))
    error_message = "Secret policy must scope access via aws:PrincipalOrgID"
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 1
    error_message = "Rotation must be configured for the secret supplying a rotation Lambda"
  }
}

run "rotation_skipped_without_lambda" {
  command = plan

  variables {
    enable_secrets_baseline = true
    org_id                  = "o-exampleorgid"
    secrets = {
      "app/static" = {}
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.this) == 1
    error_message = "The secret must be created"
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 0
    error_message = "No rotation must be configured when no rotation Lambda is supplied"
  }
}

run "disabled_creates_nothing" {
  command = plan

  # enable_secrets_baseline defaults to false; secrets default to {}.
  assert {
    condition     = length(aws_secretsmanager_secret.this) == 0
    error_message = "No secrets must be created when the module is disabled"
  }

  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 0
    error_message = "No secret policies must be created when the module is disabled"
  }
}
